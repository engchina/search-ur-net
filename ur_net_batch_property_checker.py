#!/usr/bin/env python3
"""
UR-NET バッチ空室チェックプログラム
ur_net_single_property_scraper.py を基にしたバッチ処理版
複数のURLを処理し、読みやすい結果を出力をサポート
"""

import asyncio
import sys
import json
import re
import time
import argparse
import csv
import logging
import os
import glob
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Optional, Tuple
from playwright.async_api import async_playwright

class URNetBatchChecker:
    def __init__(self, delay_seconds: float = 2.0, max_retries: int = 5, headless: bool = True):
        """
        バッチチェッカーを初期化
        
        Args:
            delay_seconds: リクエスト間の遅延時間（秒）
            max_retries: 最大リトライ回数
            headless: ヘッドレスモードを使用するか
        """
        self.delay_seconds = delay_seconds
        self.max_retries = max_retries
        self.headless = headless
        self.results = []
        
    async def extract_property_info(self, page, url: str, predefined_info: Optional[Dict] = None) -> Dict:
        """
        ページから物件情報を抽出
        
        Args:
            page: Playwrightページオブジェクト
            url: 対象URL
            predefined_info: 事前定義された物件情報（CSVから）
            
        Returns:
            物件情報を含む辞書
        """
        try:
            # 物件名を抽出
            try:
                name_element = await page.query_selector('h1.property-name')
                if name_element:
                    name = await name_element.text_content()
                    property_name = name.strip() if name else "不明な物件"
                else:
                    # バックアップセレクタを試行
                    name_element = await page.query_selector('h1, .property-title, .building-name')
                    if name_element:
                        name = await name_element.text_content()
                        property_name = name.strip() if name else "不明な物件"
                    else:
                        property_name = predefined_info.get('name', '不明な物件') if predefined_info else "不明な物件"
            except Exception as e:
                # フォールバック: タイトルから抽出
                title = await page.title()
                property_name = title.replace("（東京都）の賃貸物件｜UR賃貸住宅", "").strip()
                if not property_name:
                    property_name = predefined_info.get('name', '不明な物件') if predefined_info else "不明な物件"
            
            # 空室情報を検索 - UR-NET専用の改良されたロジック
            import re  # 明示的にreモジュールをインポート
            vacant_rooms = []
            
            # UR-NETの房间表格を特定 - 複数のパターンに対応
            room_table_selectors = [
                '.module_tables_room table tbody tr.js-log-item',  # UR-NET特有のセレクタ
                'table tbody tr.js-log-item',  # フォールバック
                '.rep_room',  # 別のフォールバック
                'table tbody tr',  # 一般的なテーブル行
                'tr',  # 最も一般的
            ]
            
            room_rows = []
            for selector in room_table_selectors:
                try:
                    rows = await page.query_selector_all(selector)
                    if rows:
                        # 房间情報を含む行をフィルタリング - より厳格な条件
                        filtered_rows = []
                        for row in rows:
                            try:
                                row_text = await row.text_content()
                                # ヘッダー行を除外
                                if row_text and not any(header in row_text for header in 
                                    ['間取図', '部屋名', '家賃', '間取り', '床面積', '階数']):
                                    # 房间情報らしい行を特定 - 価格と房间名/間取りの両方が必要
                                    has_price = re.search(r'\d{1,3}[,，]\d{3}[円日元]?', row_text)
                                    has_room_info = (re.search(r'\d+[号棟室]', row_text) or  # 房间名パターン
                                                   re.search(r'\d+[LDK]', row_text))  # 間取りパターン
                                    
                                    if has_price and has_room_info:
                                        filtered_rows.append(row)
                            except:
                                continue
                        
                        if filtered_rows:
                            room_rows = filtered_rows
                            print(f"✅ 房间行を発見: {len(filtered_rows)}行 (セレクタ: {selector})")
                            break
                except:
                    continue
            
            if not room_rows:
                print("⚠️ 房间情報が見つかりませんでした")
            
            for row in room_rows:
                try:
                    # UR-NET特有の構造に基づいて情報を抽出
                    room_info = {}
                    
                    # 房间名を抽出 - より柔軟なセレクタ
                    room_name_selectors = [
                        '.rep_room-name',
                        'td.rep_room-name', 
                        'td:nth-child(2)',  # 通常2番目のセル
                        'td:first-child + td',  # 最初のセルの次
                    ]
                    
                    room_name = None
                    for selector in room_name_selectors:
                        try:
                            element = await row.query_selector(selector)
                            if element:
                                room_name = await element.text_content()
                                if room_name and room_name.strip():
                                    room_name = room_name.strip()
                                    # 房间名らしいパターンをチェック
                                    if re.search(r'\d+[号棟室]', room_name):
                                        break
                        except:
                            continue
                    
                    # 房间名が見つからない場合、行全体から抽出を試行
                    if not room_name:
                        try:
                            row_text = await row.text_content()
                            if row_text:
                                # 房间名パターンを検索
                                room_name_match = re.search(r'(\d+[号棟]\d+[号室])', row_text)
                                if room_name_match:
                                    room_name = room_name_match.group(1)
                        except:
                            pass
                    
                    # 価格を抽出 - より包括的なセレクタ
                    price_selectors = [
                        'span.rep_room-price',  # 主要价格选择器
                        '.rep_room-price',
                        'td:nth-child(3) span.rep_room-price',
                        'td:nth-child(3)',
                        'td:nth-child(4)',  # 場合によっては4番目のセル
                    ]
                    
                    rent = None
                    for selector in price_selectors:
                        try:
                            element = await row.query_selector(selector)
                            if element:
                                rent = await element.text_content()
                                if rent and rent.strip():
                                    rent = rent.strip()
                                    # 価格らしいパターンをチェック
                                    if re.search(r'\d{1,3}[,，]\d{3}', rent):
                                        break
                        except:
                            continue
                    
                    # 価格が見つからない場合、行全体から抽出を試行
                    if not rent:
                        try:
                            row_text = await row.text_content()
                            if row_text:
                                # 価格パターンを検索
                                price_match = re.search(r'(\d{1,3}[,，]\d{3}[円日元]?)', row_text)
                                if price_match:
                                    rent = price_match.group(1)
                        except:
                            pass
                    
                    # 間取り情報を抽出 - UR-NET表格構造に基づく
                    type_selectors = [
                        'td:nth-child(4)',  # 通常間取りは4番目のセル
                        'td:nth-child(3)',  # 場合によっては3番目
                        'td:nth-child(5)',  # 場合によっては5番目
                        '.rep_room-type',
                        'td.rep_room-type',
                    ]
                    
                    room_type = None
                    for selector in type_selectors:
                        try:
                            element = await row.query_selector(selector)
                            if element:
                                text = await element.text_content()
                                if text and text.strip():
                                    text = text.strip()
                                    # 間取りパターンをチェック（より包括的）
                                    type_match = re.search(r'(\d+[SLDK]+)', text)
                                    if type_match:
                                        room_type = type_match.group(1)
                                        break
                        except:
                            continue
                    
                    # 間取りが見つからない場合、行全体から抽出を試行
                    if not room_type:
                        try:
                            row_text = await row.text_content()
                            if row_text:
                                # より包括的な間取りパターンを検索
                                type_match = re.search(r'(\d+[SLDK]+)', row_text)
                                if type_match:
                                    room_type = type_match.group(1)
                        except:
                            pass
                    
                    # 面積を抽出 - より包括的
                    area_selectors = [
                        '.rep_room-floor',
                        'td.rep_room-floor',
                        'td:nth-child(5)',
                        'td:nth-child(6)',
                    ]
                    
                    area = None
                    for selector in area_selectors:
                        try:
                            element = await row.query_selector(selector)
                            if element:
                                area = await element.text_content()
                                if area and area.strip():
                                    area = area.strip()
                                    # 面積らしいパターンをチェック
                                    if re.search(r'\d+[㎡平方米]', area):
                                        break
                        except:
                            continue
                    
                    # 面積が見つからない場合、行全体から抽出を試行
                    if not area:
                        try:
                            row_text = await row.text_content()
                            if row_text:
                                # 面積パターンを検索
                                area_match = re.search(r'(\d+[㎡平方米])', row_text)
                                if area_match:
                                    area = area_match.group(1)
                        except:
                            pass
                    
                    # 楼層情報を抽出 - より包括的
                    floor_selectors = [
                        '.rep_room-kai',
                        'td.rep_room-kai',
                        'td:nth-child(6)',
                        'td:nth-child(7)',
                        'td:last-child',
                    ]
                    
                    floor = None
                    for selector in floor_selectors:
                        try:
                            element = await row.query_selector(selector)
                            if element:
                                floor = await element.text_content()
                                if floor and floor.strip():
                                    floor = floor.strip()
                                    # 階層らしいパターンをチェック
                                    if re.search(r'\d+[階]', floor) or '/' in floor:
                                        break
                        except:
                            continue
                    
                    # 階層が見つからない場合、行全体から抽出を試行
                    if not floor:
                        try:
                            row_text = await row.text_content()
                            if row_text:
                                # 階層パターンを検索
                                floor_match = re.search(r'(\d+[階]／?\d*[階]?)', row_text)
                                if floor_match:
                                    floor = floor_match.group(1)
                        except:
                            pass
                    
                    # 空室判定 - 簡潔なロジック
                    # 房间情報表格に表示されている房间は基本的に空室とみなす
                    # （UR-NETでは空室のみ詳細情報を表示する特性を利用）
                    is_vacant = False
                    
                    # 詳細ボタンの存在をチェック
                    try:
                        detail_button = await row.query_selector('a')
                        if detail_button:
                            button_text = await detail_button.text_content()
                            button_href = await detail_button.get_attribute('href')
                            # 詳細ボタンがあれば空室
                            if (button_text and '詳細' in button_text) or \
                               (button_href and 'room.html' in button_href):
                                is_vacant = True
                    except:
                        pass
                    
                    # 詳細ボタンがなくても、価格と間取り情報があれば空室とみなす
                    if not is_vacant and rent and room_type:
                        is_vacant = True
                    
                    # 有効な房间情報がある場合に追加（物件名は除外）
                    if is_vacant and (room_type and rent):
                        room_info = {
                            'type': room_type or '不明', 
                            'rent': rent or '不明',
                            'area': area or '不明',
                            'floor': floor or '不明'
                        }
                        vacant_rooms.append(room_info)
                        print(f"🏠 空室発見: {room_info}")
                            
                except Exception as e:
                    print(f"⚠️ 房间情報抽出エラー: {e}")
                    continue
            
            # 追加情報の処理（予定義情報を優先、なければ抓取）
            scraped_info = {}
            
            # 予定義情報がある場合は抓取をスキップ
            if predefined_info and all(key in predefined_info for key in ['transportation', 'address', 'phone', 'management_years']):
                print(f"📋 予定義情報を使用: {predefined_info.get('name', '不明')}")
                scraped_info = {
                    'transportation': predefined_info['transportation'],
                    'transportation_source': '事前定義',
                    'address': predefined_info['address'],
                    'address_source': '事前定義',
                    'phone_number': predefined_info['phone'],
                    'phone_source': '事前定義',
                    'management_years': predefined_info['management_years'],
                    'management_years_source': '事前定義'
                }
            else:
                print(f"🔍 ウェブページから追加情報を抓取中...")
                
                # 交通情報を抓取
                try:
                    transportation_selectors = [
                        'dt:contains("交通") + dd',
                        '.access-info',
                        '.transportation',
                        'td:contains("交通") + td',
                        'th:contains("交通") + td',
                        '.property-access'
                    ]
                    transportation = None
                    for selector in transportation_selectors:
                        try:
                            element = await page.query_selector(selector)
                            if element:
                                transportation = await element.text_content()
                                if transportation and transportation.strip():
                                    transportation = transportation.strip()
                                    break
                        except:
                            continue
                    
                    if not transportation:
                        # 尝试从页面文本中查找交通信息
                        page_text = await page.text_content('body')
                        if page_text:
                            import re
                            # 查找包含"駅"或"線"的交通信息
                            transport_match = re.search(r'[^\n]*(?:駅|線)[^\n]*', page_text)
                            if transport_match:
                                transportation = transport_match.group().strip()
                    
                    scraped_info['transportation'] = transportation or '不明'
                    scraped_info['transportation_source'] = 'ウェブページ抓取' if transportation else '不明'
                except Exception as e:
                    scraped_info['transportation'] = '不明'
                    scraped_info['transportation_source'] = '不明'
                
                # 住所情報を抓取
                try:
                    address_selectors = [
                        'dt:contains("所在地") + dd',
                        'dt:contains("住所") + dd',
                        '.address',
                        '.location',
                        'td:contains("所在地") + td',
                        'th:contains("住所") + td',
                        '.property-address'
                    ]
                    address = None
                    for selector in address_selectors:
                        try:
                            element = await page.query_selector(selector)
                            if element:
                                address = await element.text_content()
                                if address and address.strip():
                                    address = address.strip()
                                    break
                        except:
                            continue
                    
                    scraped_info['address'] = address or '不明'
                    scraped_info['address_source'] = 'ウェブページ抓取' if address else '不明'
                except Exception as e:
                    scraped_info['address'] = '不明'
                    scraped_info['address_source'] = '不明'
                
                # 電話番号を抓取
                try:
                    phone_selectors = [
                        'dt:contains("電話") + dd',
                        'dt:contains("TEL") + dd',
                        '.phone',
                        '.tel',
                        'td:contains("電話") + td',
                        'th:contains("TEL") + td',
                        '.contact-phone'
                    ]
                    phone = None
                    for selector in phone_selectors:
                        try:
                            element = await page.query_selector(selector)
                            if element:
                                phone = await element.text_content()
                                if phone and phone.strip():
                                    phone = phone.strip()
                                    break
                        except:
                            continue
                    
                    if not phone:
                        # 尝试从页面文本中查找电话号码
                        page_text = await page.text_content('body')
                        if page_text:
                            import re
                            # 查找电话号码格式
                            phone_match = re.search(r'(?:電話|TEL|Tel|tel)[:：\s]*([0-9\-\(\)]+)', page_text)
                            if phone_match:
                                phone = phone_match.group(1).strip()
                    
                    scraped_info['phone_number'] = phone or '不明'
                    scraped_info['phone_source'] = 'ウェブページ抓取' if phone else '不明'
                except Exception as e:
                    scraped_info['phone_number'] = '不明'
                    scraped_info['phone_source'] = '不明'
                
                # 管理年数を抓取
                try:
                    management_selectors = [
                        'dt:contains("管理年数") + dd',
                        'dt:contains("築年") + dd',
                        '.management-years',
                        '.built-year',
                        'td:contains("管理年数") + td',
                        'th:contains("築年") + td',
                        '.property-age'
                    ]
                    management_years = None
                    for selector in management_selectors:
                        try:
                            element = await page.query_selector(selector)
                            if element:
                                management_years = await element.text_content()
                                if management_years and management_years.strip():
                                    management_years = management_years.strip()
                                    break
                        except:
                            continue
                    
                    scraped_info['management_years'] = management_years or '不明'
                    scraped_info['management_years_source'] = 'ウェブページ抓取' if management_years else '不明'
                except Exception as e:
                    scraped_info['management_years'] = '不明'
                    scraped_info['management_years_source'] = '不明'
            
            return {
                'url': url,
                'property_name': property_name,
                'title': await page.title() if not (predefined_info and predefined_info.get('name')) else property_name,
                'vacant_rooms': vacant_rooms,
                'total_vacant': len(vacant_rooms),
                'phone_number': scraped_info.get('phone_number', '不明'),
                'phone_source': scraped_info.get('phone_source', '不明'),
                'transportation': scraped_info.get('transportation', '不明'),
                'transportation_source': scraped_info.get('transportation_source', '不明'),
                'address': scraped_info.get('address', '不明'),
                'address_source': scraped_info.get('address_source', '不明'),
                'management_years': scraped_info.get('management_years', '不明'),
                'management_years_source': scraped_info.get('management_years_source', '不明'),
                'status': 'success'
            }
            
        except Exception as e:
            return {
                'url': url,
                'property_name': predefined_info.get('name') if predefined_info else 'Unknown',
                'title': '',
                'vacant_rooms': [],
                'total_vacant': 0,
                'phone_number': predefined_info.get('phone', '未知') if predefined_info else '未知',
                'phone_source': '预定义' if predefined_info and predefined_info.get('phone') else '未知',
                'transportation': predefined_info.get('transportation', '未知') if predefined_info else '未知',
                'transportation_source': '预定义' if predefined_info and predefined_info.get('transportation') else '未知',
                'address': predefined_info.get('address', '未知') if predefined_info else '未知',
                'address_source': '预定义' if predefined_info and predefined_info.get('address') else '未知',
                'management_years': predefined_info.get('management_years', '未知') if predefined_info else '未知',
                'management_years_source': '预定义' if predefined_info and predefined_info.get('management_years') else '未知',
                'status': 'failed',
                'error': 'Max retries exceeded'
            }
    
    async def check_single_property(self, browser, url: str, index: int, total: int, predefined_info: Optional[Dict] = None) -> Dict:
        """
        単一物件をチェック
        
        Args:
            browser: Playwrightブラウザオブジェクト
            url: 対象URL
            index: 現在のインデックス
            total: 総数
            predefined_info: 事前定義された物件情報辞書
            
        Returns:
            物件情報辞書
        """
        print(f"🔍 [{index}/{total}] チェック中: {url}")
        
        try:
            page = await browser.new_page()
            
            # ページ読み込みのリトライループ
            for attempt in range(self.max_retries):
                try:
                    print(f"   📖 ページ読み込み試行 {attempt + 1}/{self.max_retries}...")
                    await page.goto(url, wait_until='networkidle', timeout=30000)
                    await asyncio.sleep(self.delay_seconds)
                    break
                except Exception as e:
                    print(f"   ⚠️  ページ読み込みエラー（試行 {attempt + 1}）: {e}")
                    if attempt < self.max_retries - 1:
                        await asyncio.sleep(2 ** attempt)  # 指数バックオフ
                    else:
                        print(f"   ❌ ページ読み込みに失敗しました: {url}")
                        return {
                            'url': url,
                            'property_name': predefined_info.get('name') if predefined_info else '不明な物件',
                            'title': '',
                            'vacant_rooms': [],
                            'total_vacant': 0,
                            'phone_number': predefined_info.get('phone', '不明') if predefined_info else '不明',
                            'phone_source': '事前定義' if predefined_info and predefined_info.get('phone') else '不明',
                            'transportation': predefined_info.get('transportation', '不明') if predefined_info else '不明',
                            'transportation_source': '事前定義' if predefined_info and predefined_info.get('transportation') else '不明',
                            'address': predefined_info.get('address', '不明') if predefined_info else '不明',
                            'address_source': '事前定義' if predefined_info and predefined_info.get('address') else '不明',
                            'management_years': predefined_info.get('management_years', '不明') if predefined_info else '不明',
                            'management_years_source': '事前定義' if predefined_info and predefined_info.get('management_years') else '不明',
                            'status': 'failed',
                            'error': 'ページ読み込み失敗'
                        }
            
            # 情報を抽出
            result = await self.extract_property_info(page, url, predefined_info)
            await page.close()
            
            if result['status'] == 'success':
                print(f"✅ [{index}/{total}] 成功: {result['property_name']} ({result['total_vacant']}件の空室)")
                return result
            else:
                print(f"⚠️  [{index}/{total}] 抽出失敗: {url}")
                
        except Exception as e:
            print(f"❌ [{index}/{total}] エラー: {str(e)}")
            try:
                await page.close()
            except:
                pass
        
        # すべてのリトライが失敗した場合
        return {
            'url': url,
            'property_name': predefined_info.get('name') if predefined_info else '不明な物件',
            'title': '',
            'vacant_rooms': [],
            'total_vacant': 0,
            'phone_number': predefined_info.get('phone', '不明') if predefined_info else '不明',
            'phone_source': '事前定義' if predefined_info and predefined_info.get('phone') else '不明',
            'transportation': predefined_info.get('transportation', '不明') if predefined_info else '不明',
            'transportation_source': '事前定義' if predefined_info and predefined_info.get('transportation') else '不明',
            'address': predefined_info.get('address', '不明') if predefined_info else '不明',
            'address_source': '事前定義' if predefined_info and predefined_info.get('address') else '不明',
            'management_years': predefined_info.get('management_years', '不明') if predefined_info else '不明',
            'management_years_source': '事前定義' if predefined_info and predefined_info.get('management_years') else '不明',
            'status': 'failed',
            'error': 'Max retries exceeded'
        }
    
    async def check_properties(self, url_data: List[Tuple[str, str]]) -> List[Dict]:
        """
        複数の物件をバッチ処理でチェック
        
        Args:
            url_data: (URL, 物件名) タプルリスト
            
        Returns:
            結果リスト
        """
        print(f"🚀 {len(url_data)}件のUR-NET物件をバッチチェック開始...")
        print(f"⏱️  リクエスト間隔: {self.delay_seconds}秒")
        print("=" * 60)
        
        results = []
        
        async with async_playwright() as p:
            browser = await p.chromium.launch(headless=self.headless)
            
            try:
                # 各URLを順次処理
                for i, item in enumerate(url_data, 1):
                    # データ形式に応じてURLと情報を取得
                    if isinstance(item, dict):
                        url = item.get('url', '')
                        predefined_info = item
                    else:
                        url, name = item
                        predefined_info = {'name': name} if name else None
                    
                    if not url:
                        continue
                    result = await self.check_single_property(browser, url, i, len(url_data), predefined_info)
                    results.append(result)
                    
                    # レート制限のための遅延
                    if i < len(url_data):
                        print(f"⏳ {self.delay_seconds}秒待機中...")
                        await asyncio.sleep(self.delay_seconds)
                        
            finally:
                await browser.close()
        
        print(f"✅ バッチチェック完了！ {len(results)}件処理しました")
        self.results = results
        return results
    
    def print_results(self, results: List[Dict]):
        """
        打印格式化的结果
        
        Args:
            results: 检查结果列表
        """
        print("\n" + "=" * 80)
        print("🏠 UR-NET 批量空房检查结果")
        print("=" * 80)
        
        success_count = sum(1 for r in results if r['status'] == 'success')
        failed_count = len(results) - success_count
        total_vacant = sum(r['total_vacant'] for r in results if r['status'] == 'success')
        
        print(f"📊 统计信息:")
        print(f"   总检查数: {len(results)}")
        print(f"   成功: {success_count}")
        print(f"   失败: {failed_count}")
        print(f"   总空房数: {total_vacant}")
        print()
        
        # 按有无空房分组显示
        properties_with_rooms = [r for r in results if r['status'] == 'success' and r['total_vacant'] > 0]
        properties_without_rooms = [r for r in results if r['status'] == 'success' and r['total_vacant'] == 0]
        failed_properties = [r for r in results if r['status'] != 'success']
        
        # 显示有空房的房产
        if properties_with_rooms:
            print("🏠 有空房的房产:")
            print("-" * 50)
            for result in properties_with_rooms:
                print(f"\n📍 {result['property_name']}")
                print(f"   空房数量: {result['total_vacant']}个")
                
                for i, room in enumerate(result['vacant_rooms'], 1):
                    print(f"   🏠 空房 {i}:")
                    print(f"      房间: {room.get('room_name', '未知')}")
                    print(f"      租金: {room.get('rent', '未知')}")
                    print(f"      房型: {room.get('layout', '未知')}")
                    print(f"      面积: {room.get('area', '未知')}")
                    print(f"      楼层: {room.get('floor', '未知')}")
        
        # 显示无空房的房产
        if properties_without_rooms:
            print("\n🚫 无空房的房产:")
            print("-" * 50)
            for result in properties_without_rooms:
                print(f"📍 {result['property_name']}: ご紹介出来るお部屋はございません。")
        
        # 显示失败的房产
        if failed_properties:
            print("\n❌ 检查失败的房产:")
            print("-" * 50)
            for result in failed_properties:
                print(f"📍 {result['url']}: {result.get('error', '未知错误')}")
    
    def find_latest_result_file(self, results_dir: str = "results") -> Optional[str]:
        """
        最新の結果ファイルを検索
        
        Args:
            results_dir: 結果ファイルディレクトリ
            
        Returns:
            最新の結果ファイルパス（見つからない場合はNone）
        """
        try:
            if not os.path.exists(results_dir):
                return None
                
            # ur_net_results_*.json パターンのファイルを検索
            import glob
            pattern = os.path.join(results_dir, "ur_net_results_*.json")
            result_files = glob.glob(pattern)
            
            if not result_files:
                return None
                
            # ファイル名から日時を抽出してソート
            def extract_timestamp(filepath):
                filename = os.path.basename(filepath)
                # ur_net_results_20251006_231825.json から 20251006_231825 を抽出
                import re
                match = re.search(r'ur_net_results_(\d{8}_\d{6})\.json', filename)
                if match:
                    return match.group(1)
                return "00000000_000000"
            
            # 最新のファイルを取得
            latest_file = max(result_files, key=extract_timestamp)
            return latest_file
            
        except Exception as e:
            print(f"⚠️ 最新結果ファイル検索エラー: {e}")
            return None
    
    def compare_results(self, current_results: List[Dict], previous_file: str) -> Dict:
        """
        現在の結果と前回の結果を比較
        
        Args:
            current_results: 現在のチェック結果
            previous_file: 前回の結果ファイルパス
            
        Returns:
            比較結果を含む辞書
        """
        comparison_result = {
            'has_new_properties': False,
            'new_properties': [],
            'previous_file': previous_file,
            'comparison_summary': {}
        }
        
        try:
            # 前回の結果を読み込み
            with open(previous_file, 'r', encoding='utf-8') as f:
                previous_data = json.load(f)
                previous_results = previous_data.get('results', [])
            
            # 現在の空室ありの物件を取得
            current_vacant_properties = {}
            for result in current_results:
                if result.get('status') == 'success' and result.get('total_vacant', 0) > 0:
                    url = result.get('url', '')
                    current_vacant_properties[url] = {
                        'property_name': result.get('property_name', ''),
                        'total_vacant': result.get('total_vacant', 0),
                        'vacant_rooms': result.get('vacant_rooms', [])
                    }
            
            # 前回の空室ありの物件を取得
            previous_vacant_properties = {}
            for result in previous_results:
                if result.get('status') == 'success' and result.get('total_vacant', 0) > 0:
                    url = result.get('url', '')
                    previous_vacant_properties[url] = {
                        'property_name': result.get('property_name', ''),
                        'total_vacant': result.get('total_vacant', 0),
                        'vacant_rooms': result.get('vacant_rooms', [])
                    }
            
            # 新しい空室物件を検出
            new_vacant_urls = set(current_vacant_properties.keys()) - set(previous_vacant_properties.keys())
            
            # 既存物件で空室数が増加した場合も新規とみなす
            increased_vacant_urls = []
            for url in current_vacant_properties:
                if url in previous_vacant_properties:
                    current_count = current_vacant_properties[url]['total_vacant']
                    previous_count = previous_vacant_properties[url]['total_vacant']
                    if current_count > previous_count:
                        increased_vacant_urls.append(url)
            
            # 新規物件情報を収集
            all_new_urls = list(new_vacant_urls) + increased_vacant_urls
            for url in all_new_urls:
                if url in current_vacant_properties:
                    comparison_result['new_properties'].append({
                        'url': url,
                        'property_name': current_vacant_properties[url]['property_name'],
                        'total_vacant': current_vacant_properties[url]['total_vacant'],
                        'vacant_rooms': current_vacant_properties[url]['vacant_rooms'],
                        'change_type': 'new' if url in new_vacant_urls else 'increased'
                    })
            
            # 新規物件があるかどうかを判定
            comparison_result['has_new_properties'] = len(comparison_result['new_properties']) > 0
            
            # 比較サマリーを作成
            comparison_result['comparison_summary'] = {
                'previous_vacant_count': len(previous_vacant_properties),
                'current_vacant_count': len(current_vacant_properties),
                'new_vacant_properties': len(new_vacant_urls),
                'increased_vacant_properties': len(increased_vacant_urls),
                'total_new_changes': len(comparison_result['new_properties'])
            }
            
            print(f"📊 結果比較完了:")
            print(f"   前回空室物件数: {len(previous_vacant_properties)}")
            print(f"   今回空室物件数: {len(current_vacant_properties)}")
            print(f"   新規空室物件: {len(new_vacant_urls)}")
            print(f"   空室増加物件: {len(increased_vacant_urls)}")
            print(f"   メール送信必要: {'はい' if comparison_result['has_new_properties'] else 'いいえ'}")
            
        except Exception as e:
            print(f"⚠️ 結果比較エラー: {e}")
            # エラーの場合は安全のためメール送信を推奨
            comparison_result['has_new_properties'] = True
            comparison_result['comparison_summary']['error'] = str(e)
        
        return comparison_result
    
    def should_send_email(self, results: List[Dict], results_dir: str = "results") -> Tuple[bool, Dict]:
        """
        メール送信が必要かどうかを判定
        
        Args:
            results: 現在のチェック結果
            results_dir: 結果ファイルディレクトリ
            
        Returns:
            (送信必要フラグ, 判定詳細情報)
        """
        decision_info = {
            'should_send': False,
            'reason': '',
            'is_first_run': False,
            'comparison_result': None
        }
        
        # 最新の結果ファイルを検索
        latest_file = self.find_latest_result_file(results_dir)
        
        if not latest_file:
            # 初回実行の場合
            decision_info['should_send'] = True
            decision_info['reason'] = '初回実行のため'
            decision_info['is_first_run'] = True
            print("📧 初回実行検出 - メール送信を実行します")
        else:
            # 前回結果と比較
            print(f"🔍 前回結果と比較中: {latest_file}")
            comparison_result = self.compare_results(results, latest_file)
            decision_info['comparison_result'] = comparison_result
            
            if comparison_result['has_new_properties']:
                decision_info['should_send'] = True
                decision_info['reason'] = f"新規空室物件 {len(comparison_result['new_properties'])} 件検出"
                print(f"📧 新規物件検出 - メール送信を実行します")
            else:
                decision_info['should_send'] = False
                decision_info['reason'] = '新規空室物件なし'
                print("📧 新規物件なし - メール送信をスキップします")
        
        return decision_info['should_send'], decision_info

    def save_results(self, results: List[Dict], output_format: str = 'json', output_path: Optional[str] = None):
        """
        結果をファイルに保存
        
        Args:
            results: チェック結果リスト
            output_format: 出力形式 ('json', 'csv', 'txt')
            output_path: 出力ファイルパス（Noneの場合は自動生成）
        """
        if not output_path:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            # 确保输出目录存在
            results_dir = "/app/results" if os.path.exists("/app") else "results"
            os.makedirs(results_dir, exist_ok=True)
            # 使用与 shell 脚本匹配的文件名格式
            output_path = os.path.join(results_dir, f"ur_net_results_{timestamp}.{output_format}")
        
        print(f"💾 結果を保存中: {output_path}")
        
        try:
            if output_format == 'json':
                result_data = {
                    'timestamp': datetime.now().isoformat(),
                    'total_checked': len(results),
                    'total_vacant_rooms': sum(r['total_vacant'] for r in results if r['status'] == 'success'),
                    'results': results
                }
                with open(output_path, 'w', encoding='utf-8') as f:
                    json.dump(result_data, f, ensure_ascii=False, indent=2)
                    
            elif output_format == 'csv':
                import csv
                with open(output_path, 'w', newline='', encoding='utf-8-sig') as f:
                    if results:
                        writer = csv.DictWriter(f, fieldnames=results[0].keys())
                        writer.writeheader()
                        writer.writerows(results)
                        
            elif output_format == 'txt':
                with open(output_path, 'w', encoding='utf-8') as f:
                    for result in results:
                        f.write(f"物件名: {result.get('property_name', '不明')}\n")
                        f.write(f"URL: {result.get('url', '不明')}\n")
                        f.write(f"空室数: {result.get('total_vacant', 0)}件\n")
                        f.write(f"状態: {result.get('status', '不明')}\n")
                        f.write(f"電話番号: {result.get('phone_number', '不明')}\n")
                        f.write(f"交通: {result.get('transportation', '不明')}\n")
                        f.write(f"住所: {result.get('address', '不明')}\n")
                        f.write(f"管理年数: {result.get('management_years', '不明')}\n")
                        f.write(f"更新日時: {result.get('last_updated', '不明')}\n")
                        
                        if result.get('vacant_rooms'):
                            f.write("空室詳細:\n")
                            for room in result['vacant_rooms']:
                                f.write(f"  - {room}\n")
                        f.write("-" * 50 + "\n\n")
            
            print(f"✅ 結果を正常に保存しました: {output_path}")
            
        except Exception as e:
            print(f"❌ 結果の保存に失敗しました: {e}")

def parse_urls_from_text(text: str) -> List[str]:
    """
    テキストからUR-NET URLを抽出
    
    Args:
        text: 入力テキスト
        
    Returns:
        URLリスト
    """
    # UR-NET URLパターン
    url_pattern = r'https?://www\.ur-net\.go\.jp/[^\s]+'
    urls = re.findall(url_pattern, text)
    return urls

def parse_urls_from_csv(csv_file: str) -> List[Dict]:
    """
    CSVファイルからURLと物件情報を読み込む
    
    Args:
        csv_file: CSVファイルパス
        
    Returns:
        物件情報辞書リスト
    """
    import csv
    
    url_data = []
    print(f"📄 CSVファイルを読み込み中: {csv_file}")
    try:
        with open(csv_file, 'r', encoding='utf-8') as f:
            # 最初の行を確認してヘッダーがあるかチェック
            first_line = f.readline().strip()
            f.seek(0)  # ファイルポインタをリセット
            
            print(f"📄 最初の行: {first_line}")
            
            # urls.txt形式の特別処理（No.,物件名,対象空室数,最寄駅,住所,電話番号,管理年数,URL）
            if 'No.,物件名,対象空室数,最寄駅,住所,電話番号,管理年数,URL' in first_line:
                print("📄 urls.txt形式を検出しました")
                reader = csv.reader(f)
                next(reader)  # ヘッダー行をスキップ
                for row_num, row in enumerate(reader, 2):  # 2行目から開始
                    print(f"📄 行{row_num}: {len(row)}列 - {row}")
                    if len(row) >= 8:  # 8列必要
                        url = row[7].strip() if len(row) > 7 else ""  # URLは8番目の列（インデックス7）
                        if url and url.startswith('http'):
                            info = {
                                'url': url,
                                'name': row[1].strip() if len(row) > 1 else '不明',  # 物件名
                                'transportation': row[3].strip() if len(row) > 3 else '不明',  # 最寄駅
                                'address': row[4].strip() if len(row) > 4 else '不明',  # 住所
                                'phone': row[5].strip() if len(row) > 5 else '不明',  # 電話番号
                                'management_years': row[6].strip() if len(row) > 6 else '不明'  # 管理年数
                            }
                            url_data.append(info)
                            print(f"✅ 読み込み成功: {info['name']} - {url}")
                            print(f"   交通: {info['transportation']}")
                            print(f"   住所: {info['address']}")
                            print(f"   電話: {info['phone']}")
                            print(f"   管理年数: {info['management_years']}")
                return url_data
            
            # ヘッダーがない場合は、インデックスベースで処理
            if not first_line.startswith('url,') and not first_line.startswith('URL,') and not first_line.startswith('name,'):
                print("📄 ヘッダーが見つかりません。インデックスベースで処理します")
                reader = csv.reader(f)
                for row_num, row in enumerate(reader):
                    print(f"📄 行{row_num+1}: {len(row)}列 - {row}")
                    if len(row) >= 8:  # 少なくとも8列必要
                        url = row[7] if len(row) > 7 else ""  # URLは8番目の列（インデックス7）
                        if url and url.startswith('http'):
                            info = {'url': url}
                            if len(row) > 0: info['name'] = row[0].strip()
                            if len(row) > 5: info['phone'] = row[5].strip()
                            if len(row) > 3: info['transportation'] = row[3].strip()
                            if len(row) > 4: info['address'] = row[4].strip()
                            if len(row) > 6: info['management_years'] = row[6].strip()
                            url_data.append(info)
                            print(f"✅ 読み込み成功: {info.get('name', '不明')} - {url}")
                return url_data
            
            # ヘッダーがある場合はDictReaderを使用
            reader = csv.DictReader(f)
            print(f"📄 フィールド名: {reader.fieldnames}")
            for row_num, row in enumerate(reader):
                # URLカラムを探す
                url = None
                for key in ['url', 'URL', 'リンク', 'link']:
                    if key in row and row[key]:
                        url = row[key].strip()
                        break
                
                if url:
                    # 物件情報を抽出
                    info = {'url': url}
                    
                    # 名称カラムを探す
                    for key in ['name', '名称', '物件名', 'property_name', '団地名']:
                        if key in row and row[key]:
                            info['name'] = row[key].strip()
                            break
                    
                    # 電話番号カラムを探す
                    for key in ['phone', '電話', '電話番号', 'tel', 'TEL']:
                        if key in row and row[key]:
                            info['phone'] = row[key].strip()
                            break
                    
                    # 交通カラムを探す
                    for key in ['transportation', '交通', '交通機関', 'access', '最寄駅']:
                        if key in row and row[key]:
                            info['transportation'] = row[key].strip()
                            break
                    
                    # 住所カラムを探す
                    for key in ['address', '住所', '所在地', 'location']:
                        if key in row and row[key]:
                            info['address'] = row[key].strip()
                            break
                    
                    # 管理年数カラムを探す
                    for key in ['management_years', '管理年数', 'years', '年数']:
                        if key in row and row[key]:
                            info['management_years'] = row[key].strip()
                            break
                    
                    url_data.append(info)
                    print(f"📄 行{row_num+1}: {info.get('name', '不明')} - {url}")
        
        print(f"📊 CSVファイルから{len(url_data)}件の物件情報を読み込みました")
        return url_data
        
    except FileNotFoundError:
        print(f"❌ CSVファイルが見つかりません: {csv_file}")
        return []
    except Exception as e:
        print(f"❌ CSVファイルの読み込みエラー: {e}")
        import traceback
        traceback.print_exc()
        return []

async def main():
    """
    メイン関数 - コマンドラインインターフェース
    """
    parser = argparse.ArgumentParser(
        description='UR-NETバッチ空室チェックツール',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用例:
  # URLリストを直接指定
  python ur_net_batch_property_checker.py -u "https://www.ur-net.go.jp/..." "https://www.ur-net.go.jp/..."
  
  # ファイルからURLを読み込む
  python ur_net_batch_property_checker.py -f urls.txt
  
  # CSVファイルから物件情報を読み込む
  python ur_net_batch_property_checker.py -c properties.csv
  
  # 出力形式を指定
  python ur_net_batch_property_checker.py -u "https://..." -o csv -p results.csv
  
  # 遅延時間を設定（デフォルト2秒）
  python ur_net_batch_property_checker.py -u "https://..." -d 3
  
  # ヘッドレスモードを無効化（ブラウザを表示）
  python ur_net_batch_property_checker.py -u "https://..." --no-headless
        """
    )
    
    # 引数を定義
    parser.add_argument('-u', '--urls', nargs='+', help='UR-NET物件URL')
    parser.add_argument('-f', '--file', help='URLリストファイル')
    parser.add_argument('-c', '--csv', help='物件情報CSVファイル')
    parser.add_argument('-o', '--output-format', choices=['json', 'csv', 'txt'], default='json', help='出力形式')
    parser.add_argument('-p', '--output-path', help='出力ファイルパス')
    parser.add_argument('-d', '--delay', type=float, default=2.0, help='リクエスト間の遅延時間（秒）')
    parser.add_argument('--max-retries', type=int, default=5, help='最大リトライ回数')
    parser.add_argument('--no-headless', action='store_true', help='ヘッドレスモードを無効化')
    parser.add_argument('--verbose', '-v', action='store_true', help='詳細なログ出力')
    
    args = parser.parse_args()
    
    # ロギング設定
    if args.verbose:
        logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
    else:
        logging.basicConfig(level=logging.WARNING, format='%(asctime)s - %(levelname)s - %(message)s')
    
    # URLリストを収集
    url_data = []
    
    if args.urls:
        # 直接URLを指定
        for url in args.urls:
            url_data.append({'url': url})
        print(f"📋 {len(url_data)}件のURLをコマンドラインから読み込みました")
    
    elif args.file:
        # ファイルから読み込む
        try:
            with open(args.file, 'r', encoding='utf-8') as f:
                content = f.read()
                urls = parse_urls_from_text(content)
                url_data = [{'url': url} for url in urls]
            print(f"📄 {args.file}から{len(url_data)}件のURLを読み込みました")
        except Exception as e:
            print(f"❌ ファイル読み込みエラー: {e}")
            return
    
    elif args.csv:
        # CSVファイルから読み込む
        url_data = parse_urls_from_csv(args.csv)
        if not url_data:
            print("❌ CSVファイルからデータを読み込めませんでした")
            return
    
    else:
        print("❌ URL、ファイル、またはCSVファイルを指定してください")
        parser.print_help()
        return
    
    if not url_data:
        print("❌ 有効なURLが見つかりませんでした")
        return
    
    print(f"\n🎯 合計{len(url_data)}件の物件をチェックします")
    print(f"⏱️  遅延時間: {args.delay}秒")
    print(f"🔄 最大リトライ回数: {args.max_retries}")
    print(f"👻 ヘッドレスモード: {'無効' if args.no_headless else '有効'}")
    print("=" * 60)
    
    # バッチチェッカーを作成
    checker = URNetBatchChecker(
        delay_seconds=args.delay,
        max_retries=args.max_retries,
        headless=not args.no_headless
    )
    
    try:
        # チェックを実行
        urls = [item['url'] for item in url_data]
        results = await checker.check_properties(url_data)
        
        # 統計情報を表示
        successful = sum(1 for r in results if r['status'] == 'success')
        failed = sum(1 for r in results if r['status'] == 'failed')
        total_vacant = sum(r.get('total_vacant', 0) for r in results if r['status'] == 'success')
        
        print("\n" + "=" * 60)
        print("📊 チェック結果サマリー:")
        print(f"  ✅ 成功: {successful}件")
        print(f"  ❌ 失敗: {failed}件")
        print(f"  🏠 総空室数: {total_vacant}件")
        print("=" * 60)
        
        # 結果を保存
        checker.save_results(results, args.output_format, args.output_path)
        
        # メール送信の判定
        should_send, email_info = checker.should_send_email(results)
        if should_send:
            print(f"\n📧 メール送信条件を満たしました: {email_info['reason']}")
            if email_info.get('new_properties'):
                print(f"   新規物件数: {len(email_info['new_properties'])}")
            if email_info.get('increased_properties'):
                print(f"   空室増加物件数: {len(email_info['increased_properties'])}")
            print("   メール送信処理を実行してください")
        else:
            print(f"\n📧 メール送信をスキップ: {email_info['reason']}")
        
        # 空室あり物件を表示
        vacant_properties = [r for r in results if r.get('total_vacant', 0) > 0]
        if vacant_properties:
            print(f"\n🎉 空室あり物件 ({len(vacant_properties)}件):")
            for prop in vacant_properties:
                print(f"  🏢 {prop['property_name']}: {prop['total_vacant']}件の空室")
                print(f"     URL: {prop['url']}")
                print(f"     電話: {prop.get('phone_number', '不明')}")
                print(f"     交通: {prop.get('transportation', '不明')}")
                print()
        else:
            print("\n😔 空室あり物件は見つかりませんでした")
    
    except KeyboardInterrupt:
        print("\n\n⚠️  ユーザーによって中断されました")
    except Exception as e:
        print(f"\n❌ エラーが発生しました: {e}")
        if args.verbose:
            import traceback
            traceback.print_exc()

if __name__ == "__main__":
    # Windowsで実行する場合のエラー対策
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n\n⚠️ ユーザーによって中断されました")
    except Exception as e:
        print(f"\n❌ 予期しないエラーが発生しました: {e}")
        import traceback
        traceback.print_exc()
