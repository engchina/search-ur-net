#!/usr/bin/env python3
"""
UR-NET 空室検査結果メール送信プログラム
HTML形式の検査結果メール送信をサポート
"""

import smtplib
import json
import os
import argparse
import sys
from datetime import datetime
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.header import Header
from typing import Dict, List, Optional
import time

# 尝试导入 python-dotenv，如果没有安装则跳过
try:
    from dotenv import load_dotenv
    load_dotenv()  # 加载 .env 文件
except ImportError:
    print("⚠️  python-dotenv 未安装，将使用系统环境变量")
    print("   安装命令: pip install python-dotenv")

class URNetEmailSender:
    def __init__(self, smtp_config: Dict[str, str]):
        """
        メール送信機を初期化
        
        Args:
            smtp_config: SMTP設定辞書
        """
        self.smtp_server = smtp_config.get('server', 'smtp.email.ap-osaka-1.oci.oraclecloud.com')
        self.smtp_port = int(smtp_config.get('port', 587))
        self.smtp_user = smtp_config.get('user')
        self.smtp_pass = smtp_config.get('password')
        self.from_addr = smtp_config.get('from_addr', 'no-reply@k8scloud.site')
        self.max_retries = int(smtp_config.get('max_retries', 3))
        
        # BCC 地址配置（支持多个地址，用逗号分隔）
        bcc_addr = smtp_config.get('bcc_addr', '')
        self.bcc_addrs = [addr.strip() for addr in bcc_addr.split(',') if addr.strip()] if bcc_addr else []
        
    def format_results_to_html(self, results_data: Dict) -> str:
        """
        検査結果をHTML形式にフォーマット
        
        Args:
            results_data: 検査結果データ
            
        Returns:
            HTML形式のメール内容
        """
        # JSONファイルから読み込んだデータの場合
        if 'results' in results_data:
            results = results_data['results']
            timestamp = results_data.get('timestamp', datetime.now().isoformat())
            total_checked = results_data.get('total_checked', len(results))
            total_vacant_rooms = results_data.get('total_vacant_rooms', 0)
        else:
            # 直接渡された結果リストの場合
            results = results_data
            timestamp = datetime.now().isoformat()
            total_checked = len(results)
            total_vacant_rooms = sum(r.get('total_vacant', 0) for r in results if r.get('status') == 'success')
        
        # 結果を分類
        properties_with_rooms = [r for r in results if r.get('status') == 'success' and r.get('total_vacant', 0) > 0]
        properties_without_rooms = [r for r in results if r.get('status') == 'success' and r.get('total_vacant', 0) == 0]
        failed_properties = [r for r in results if r.get('status') != 'success']
        
        success_count = len(properties_with_rooms) + len(properties_without_rooms)
        failed_count = len(failed_properties)
        
        html_content = f"""
<!DOCTYPE html>
<html lang="ja">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>UR-NET 空室検査結果報告</title>
    <style>
        body {{
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            line-height: 1.6;
            color: #333;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
            background-color: #f5f5f5;
        }}
        .container {{
            background-color: white;
            border-radius: 10px;
            padding: 30px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }}
        .header {{
            text-align: center;
            border-bottom: 3px solid #007bff;
            padding-bottom: 20px;
            margin-bottom: 30px;
        }}
        .header h1 {{
            color: #007bff;
            margin: 0;
            font-size: 28px;
        }}
        .timestamp {{
            color: #666;
            font-size: 14px;
            margin-top: 10px;
        }}
        .stats {{
            background: linear-gradient(135deg, #f8f9fa 0%, #e9ecef 100%);
            color: black;
            padding: 20px;
            border-radius: 8px;
            margin-bottom: 30px;
            border: 1px solid #dee2e6;
        }}
        .stats h2 {{
            margin: 0 0 15px 0;
            font-size: 20px;
        }}
        .stats-grid {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 15px;
        }}
        .stat-item {{
            text-align: center;
            background: rgba(0,0,0,0.05);
            padding: 10px;
            border-radius: 5px;
        }}
        .stat-number {{
            font-size: 24px;
            font-weight: bold;
            display: block;
        }}
        .stat-label {{
            font-size: 12px;
            opacity: 0.7;
        }}
        .section {{
            margin-bottom: 30px;
        }}
        .section h2 {{
            color: #28a745;
            border-left: 4px solid #28a745;
            padding-left: 15px;
            margin-bottom: 20px;
        }}
        .section.no-rooms h2 {{
            color: #ffc107;
            border-left-color: #ffc107;
        }}
        .section.failed h2 {{
            color: #dc3545;
            border-left-color: #dc3545;
        }}
        .property {{
            background: #f8f9fa;
            border: 1px solid #dee2e6;
            border-radius: 8px;
            padding: 20px;
            margin-bottom: 20px;
        }}
        .property-name {{
            font-size: 18px;
            font-weight: bold;
            color: #007bff;
            margin-bottom: 10px;
        }}
        .room {{
            background: white;
            border: 1px solid #e9ecef;
            border-radius: 5px;
            padding: 15px;
            margin: 10px 0;
        }}
        .room-title {{
            font-weight: bold;
            color: #28a745;
            margin-bottom: 8px;
        }}
        .room-details {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
            gap: 10px;
        }}
        .room-detail {{
            background: #f8f9fa;
            padding: 8px;
            border-radius: 3px;
            text-align: center;
        }}
        .room-detail-label {{
            font-size: 12px;
            color: #666;
            display: block;
        }}
        .room-detail-value {{
            font-weight: bold;
            color: #333;
        }}
        .property-info {{
            background: #e3f2fd;
            border: 1px solid #bbdefb;
            border-radius: 6px;
            padding: 15px;
            margin: 15px 0;
        }}
        .property-info-grid {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 12px;
        }}
        .property-info-item {{
            background: white;
            padding: 10px;
            border-radius: 4px;
            border-left: 3px solid #2196f3;
        }}
        .property-info-label {{
            font-size: 12px;
            color: #666;
            display: block;
            margin-bottom: 4px;
        }}
        .property-info-value {{
            font-weight: bold;
            color: #333;
            word-break: break-all;
        }}
        .property-info-source {{
            font-size: 10px;
            color: #999;
            font-style: italic;
            margin-top: 2px;
        }}
        .no-rooms-list {{
            background: #fff3cd;
            border: 1px solid #ffeaa7;
            border-radius: 8px;
            padding: 20px;
        }}
        .no-rooms-item {{
            padding: 8px 0;
            border-bottom: 1px solid #ffeaa7;
        }}
        .no-rooms-item:last-child {{
            border-bottom: none;
        }}
        .failed-list {{
            background: #f8d7da;
            border: 1px solid #f5c6cb;
            border-radius: 8px;
            padding: 20px;
        }}
        .failed-item {{
            padding: 8px 0;
            border-bottom: 1px solid #f5c6cb;
        }}
        .failed-item:last-child {{
            border-bottom: none;
        }}
        .footer {{
            text-align: center;
            margin-top: 40px;
            padding-top: 20px;
            border-top: 1px solid #dee2e6;
            color: #666;
            font-size: 14px;
        }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🏠 UR-NET 空室検査結果報告</h1>
            <div class="timestamp">生成時間: {datetime.fromisoformat(timestamp.replace('Z', '+00:00')).strftime('%Y年%m月%d日 %H:%M:%S')}</div>
        </div>
        
        <div class="stats">
            <h2>📊 統計情報</h2>
            <div class="stats-grid">
                <div class="stat-item">
                    <span class="stat-label">総検査数：</span>
                    <span class="stat-number">{total_checked}</span>
                </div>
                <div class="stat-item">
                    <span class="stat-label">成功：</span>
                    <span class="stat-number">{success_count}</span>
                </div>
                <div class="stat-item">
                    <span class="stat-label">失敗：</span>
                    <span class="stat-number">{failed_count}</span>
                </div>
                <div class="stat-item">
                    <span class="stat-label">総空室数：</span>
                    <span class="stat-number">{total_vacant_rooms}</span>
                </div>
            </div>
        </div>
"""
        
        # 空室がある物件
        if properties_with_rooms:
            html_content += """
        <div class="section">
            <h2>🏠 空室がある物件</h2>
"""
            for prop in properties_with_rooms:
                html_content += f"""
            <div class="property">
                <div class="property-name">📍 {prop.get('property_name', '不明')}</div>
                <div style="margin-bottom: 15px;">空室数: <strong>{prop.get('total_vacant', 0)}個</strong></div>
                
                <div class="property-info">
                    <div class="property-info-grid">
                        <div class="property-info-item">
                            <span class="property-info-label">🚇 交通</span>
                            <div class="property-info-value">{prop.get('transportation', '不明')}</div>
                        </div>
                        <div class="property-info-item">
                            <span class="property-info-label">📍 住所</span>
                            <div class="property-info-value">{prop.get('address', '不明')}</div>
                        </div>
                        <div class="property-info-item">
                            <span class="property-info-label">📞 電話番号</span>
                            <div class="property-info-value">{prop.get('phone_number', '不明')}</div>
                        </div>
                        <div class="property-info-item">
                            <span class="property-info-label">🏢 管理年数</span>
                            <div class="property-info-value">{prop.get('management_years', '不明')}</div>
                        </div>
                        <div class="property-info-item">
                            <span class="property-info-label">🔗 詳細URL</span>
                            <div class="property-info-value">
                                <a href="{prop.get('url', '#')}" target="_blank" style="color: #007bff; text-decoration: none;">
                                    {prop.get('url', '不明')}
                                </a>
                            </div>
                        </div>
                    </div>
                </div>
"""
                for i, room in enumerate(prop.get('vacant_rooms', []), 1):
                    html_content += f"""
                <div class="room">
                    <div class="room-title">🏠 空室 {i}</div>
                    <div class="room-details">
                        <div class="room-detail">
                            <span class="room-detail-label">家賃(共益費)</span>
                            <span class="room-detail-value">{room.get('rent', '不明')}</span>
                        </div>
                        <div class="room-detail">
                            <span class="room-detail-label">間取り</span>
                            <span class="room-detail-value">{room.get('type', '不明')}</span>
                        </div>
                        <div class="room-detail">
                            <span class="room-detail-label">床面積</span>
                            <span class="room-detail-value">{room.get('area', '不明')}</span>
                        </div>
                        <div class="room-detail">
                            <span class="room-detail-label">階数</span>
                            <span class="room-detail-value">{room.get('floor', '不明')}</span>
                        </div>
                    </div>
                </div>
"""
                html_content += "            </div>\n"
            html_content += "        </div>\n"
        
        # 空室なしの物件
        if properties_without_rooms:
            html_content += """
        <div class="section no-rooms">
            <h2>🚫 空室なしの物件</h2>
"""
            for prop in properties_without_rooms:
                html_content += f"""
            <div class="property">
                <div class="property-name">📍 {prop.get('property_name', '未知')}</div>
                <div style="margin-bottom: 15px; color: #856404; font-weight: bold;">状態: ご紹介出来るお部屋はございません。</div>
                
                <div class="property-info">
                    <div class="property-info-grid">
                        <div class="property-info-item">
                            <span class="property-info-label">🚇 交通</span>
                            <div class="property-info-value">{prop.get('transportation', '未知')}</div>
                        </div>
                        <div class="property-info-item">
                            <span class="property-info-label">📍 住所</span>
                            <div class="property-info-value">{prop.get('address', '未知')}</div>
                        </div>
                        <div class="property-info-item">
                            <span class="property-info-label">📞 電話番号</span>
                            <div class="property-info-value">{prop.get('phone_number', '未知')}</div>
                        </div>
                        <div class="property-info-item">
                            <span class="property-info-label">🏢 管理年数</span>
                            <div class="property-info-value">{prop.get('management_years', '未知')}</div>
                        </div>
                        <div class="property-info-item">
                            <span class="property-info-label">🔗 詳細URL</span>
                            <div class="property-info-value">
                                <a href="{prop.get('url', '#')}" target="_blank" style="color: #007bff; text-decoration: none;">
                                    {prop.get('url', '未知')}
                                </a>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
"""
            html_content += """
        </div>
"""
        
        # 失敗した物件
        if failed_properties:
            html_content += """
        <div class="section failed">
            <h2>❌ 検査失敗の物件</h2>
"""
            for prop in failed_properties:
                html_content += f"""
            <div class="property">
                <div class="property-name">📍 {prop.get('property_name', '未知')}</div>
                <div style="margin-bottom: 15px; color: #721c24; font-weight: bold;">エラー: {prop.get('error', '不明なエラー')}</div>
                
                <div class="property-info">
                    <div class="property-info-grid">
                        <div class="property-info-item">
                            <span class="property-info-label">🚇 交通信息</span>
                            <div class="property-info-value">{prop.get('transportation', '未知')}</div>
                            <div class="property-info-source">({prop.get('transportation_source', '未知')})</div>
                        </div>
                        <div class="property-info-item">
                            <span class="property-info-label">📍 地址</span>
                            <div class="property-info-value">{prop.get('address', '未知')}</div>
                            <div class="property-info-source">({prop.get('address_source', '未知')})</div>
                        </div>
                        <div class="property-info-item">
                            <span class="property-info-label">📞 联系电话</span>
                            <div class="property-info-value">{prop.get('phone_number', '未知')}</div>
                            <div class="property-info-source">({prop.get('phone_source', '未知')})</div>
                        </div>
                        <div class="property-info-item">
                            <span class="property-info-label">🏢 管理年数</span>
                            <div class="property-info-value">{prop.get('management_years', '未知')}</div>
                            <div class="property-info-source">({prop.get('management_years_source', '未知')})</div>
                        </div>
                        <div class="property-info-item">
                            <span class="property-info-label">🔗 詳細URL</span>
                            <div class="property-info-value">
                                <a href="{prop.get('url', '#')}" target="_blank" style="color: #007bff; text-decoration: none;">
                                    {prop.get('url', '未知')}
                                </a>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
"""
            html_content += """
        </div>
"""
        
        html_content += """
        <div class="footer">
            <p>この報告書は UR-NET バッチ空室検査プログラムにより自動生成されました</p>
            <p>ご質問がある場合は、システム管理者にお問い合わせください</p>
        </div>
    </div>
</body>
</html>
"""
        
        return html_content
    
    def format_text_results(self, text_results: str) -> str:
        """
        テキスト形式の結果をHTMLに変換
        
        Args:
            text_results: テキスト形式の検査結果
            
        Returns:
            HTML形式のメール内容
        """
        # 简单的文本到HTML转换
        html_content = f"""
<!DOCTYPE html>
<html lang="ja">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>UR-NET 空室検査結果報告</title>
    <style>
        body {{
            font-family: 'MS PGothic', 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            line-height: 1.6;
            color: #333;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
            background-color: #f5f5f5;
        }}
        .container {{
            background-color: white;
            border-radius: 10px;
            padding: 30px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }}
        .header {{
            text-align: center;
            border-bottom: 3px solid #007bff;
            padding-bottom: 20px;
            margin-bottom: 30px;
        }}
        .header h1 {{
            color: #007bff;
            margin: 0;
            font-size: 28px;
        }}
        .content {{
            background: #f8f9fa;
            border: 1px solid #dee2e6;
            border-radius: 8px;
            padding: 20px;
            white-space: pre-wrap;
            font-family: 'Courier New', monospace;
            font-size: 14px;
            line-height: 1.4;
        }}
        .footer {{
            text-align: center;
            margin-top: 40px;
            padding-top: 20px;
            border-top: 1px solid #dee2e6;
            color: #666;
            font-size: 14px;
        }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🏠 UR-NET 空室検査結果報告</h1>
            <div style="color: #666; font-size: 14px; margin-top: 10px;">
                生成時間: {datetime.now().strftime('%Y年%m月%d日 %H:%M:%S')}
            </div>
        </div>
        
        <div class="content">{text_results}</div>
        
        <div class="footer">
            <p>この報告書は UR-NET バッチ空室検査プログラムにより自動生成されました</p>
            <p>ご質問がある場合は、システム管理者にお問い合わせください</p>
        </div>
    </div>
</body>
</html>
"""
        return html_content
    
    def send_email(self, to_addr: str, subject: str, html_content: str, 
                   text_content: Optional[str] = None, bcc_addrs: Optional[List[str]] = None) -> bool:
        """
        メールを送信
        
        Args:
            to_addr: 宛先メールアドレス
            subject: メール件名
            html_content: HTML内容
            text_content: プレーンテキスト内容（オプション）
            bcc_addrs: BCC地址列表（オプション、未指定时使用配置的默认BCC地址）
            
        Returns:
            送信成功かどうか
        """
        print(f"📧 メールを準備中: {to_addr}")
        print(f"📧 メール件名: {subject}")
        
        # 使用传入的 BCC 地址，如果没有则使用配置的默认 BCC 地址
        actual_bcc_addrs = bcc_addrs if bcc_addrs is not None else self.bcc_addrs
        if actual_bcc_addrs:
            print(f"📧 BCC 地址: {', '.join(actual_bcc_addrs)}")
        
        for attempt in range(self.max_retries):
            try:
                # メールオブジェクトを作成
                msg = MIMEMultipart('alternative')
                msg['From'] = Header(self.from_addr)
                msg['To'] = Header(to_addr)
                msg['Subject'] = Header(subject, 'utf-8')
                
                # 添加 BCC 头部（仅用于显示，实际发送时会在 sendmail 中处理）
                if actual_bcc_addrs:
                    msg['Bcc'] = Header(', '.join(actual_bcc_addrs))
                
                # プレーンテキストバージョンを追加（提供されている場合）
                if text_content:
                    text_part = MIMEText(text_content, 'plain', 'utf-8')
                    msg.attach(text_part)
                
                # HTMLバージョンを追加
                html_part = MIMEText(html_content, 'html', 'utf-8')
                msg.attach(html_part)
                
                # 构建所有收件人列表（包括 TO 和 BCC）
                all_recipients = [to_addr] + actual_bcc_addrs
                
                # SMTPサーバーに接続して送信
                with smtplib.SMTP(self.smtp_server, self.smtp_port) as server:
                    server.starttls()  # TLS暗号化を有効化
                    server.login(self.smtp_user, self.smtp_pass)
                    server.sendmail(self.from_addr, all_recipients, msg.as_string())
                
                print(f"✅ メール送信成功！(試行 {attempt + 1}/{self.max_retries})")
                if actual_bcc_addrs:
                    print(f"✅ BCC 送信成功: {len(actual_bcc_addrs)} 个地址")
                return True
                
            except Exception as e:
                print(f"❌ メール送信失敗 (試行 {attempt + 1}/{self.max_retries}): {e}")
                if attempt < self.max_retries - 1:
                    wait_time = (attempt + 1) * 2  # 増加待機時間
                    print(f"⏳ {wait_time} 秒待機して再試行...")
                    time.sleep(wait_time)
                else:
                    print("❌ すべての再試行が失敗しました")
                    return False
        
        return False

def load_config_from_env() -> Dict[str, str]:
    """
    環境変数からSMTP設定を読み込む
    
    Returns:
        SMTP設定辞書
    """
    # 必须的配置项检查
    smtp_user = os.getenv('SMTP_USER')
    smtp_pass = os.getenv('SMTP_PASS')
    
    if not smtp_user or not smtp_pass:
        print("❌ 错误: SMTP_USER 和 SMTP_PASS 环境变量必须设置")
        print("   请在 .env 文件中配置这些值，或设置系统环境变量")
        sys.exit(1)
    
    return {
        'server': os.getenv('SMTP_SERVER', 'smtp.email.ap-osaka-1.oci.oraclecloud.com'),
        'port': os.getenv('SMTP_PORT', '587'),
        'user': smtp_user,
        'password': smtp_pass,
        'from_addr': os.getenv('FROM_ADDR', 'no-reply@k8scloud.site'),
        'max_retries': os.getenv('MAX_RETRIES', '3'),
        'bcc_addr': os.getenv('BCC_ADDR', '')
    }

def load_results_from_json(file_path: str) -> Dict:
    """
    JSONファイルから検査結果を読み込む
    
    Args:
        file_path: JSONファイルパス
        
    Returns:
        検査結果データ
    """
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except FileNotFoundError:
        print(f"❌ ファイルが見つかりません: {file_path}")
        return {}
    except json.JSONDecodeError as e:
        print(f"❌ JSON解析に失敗しました: {e}")
        return {}
    except Exception as e:
        print(f"❌ ファイルの読み込みに失敗しました: {e}")
        return {}

def main():
    """
    メイン関数 - コマンドライン引数を処理し、メール送信を実行
    
    使用例:
        python ur_net_email_sender.py --results results.json --to your@email.com
        python ur_net_email_sender.py --results results.json --to your@email.com --subject "カスタム件名"
        python ur_net_email_sender.py --results results.json --to your@email.com --text-only
    """
    parser = argparse.ArgumentParser(description='UR-NET 空室検査結果メール送信プログラム')
    parser.add_argument('-j', '--json', help='JSON結果ファイルパス')
    parser.add_argument('-t', '--text', help='テキスト結果ファイルパス')
    parser.add_argument('-to', '--to-addr', help='宛先メールアドレス')
    parser.add_argument('-s', '--subject', default='UR-NET空室検査結果報告', help='メール件名')
    parser.add_argument('--test', action='store_true', help='テストメールを送信')
    
    args = parser.parse_args()
    
    # SMTP設定を読み込む
    smtp_config = load_config_from_env()
    
    # メール送信クラスを作成
    sender = URNetEmailSender(smtp_config)
    
    # 宛先を決定
    to_addr = args.to_addr or os.getenv('DEFAULT_TO_ADDR')
    
    # メール内容を準備
    if args.test:
        # テストメールを送信
        test_results = """
================================================================================
🏠 UR-NET バッチ空室検査結果
================================================================================
📊 統計情報:
   総検査数: 23
   成功: 23
   失敗: 0
   総空室数: 2

🏠 空室ありの物件:
--------------------------------------------------

📍 東大島駅前ハイツ
   空室数: 1個
   🏠 空室 1:
      部屋: 2号棟211号室
      賃料: 166,500円
      間取り: 2LDK
      面積: 66㎡
      階数: 2階

📍 シティコート世田谷給田
   空室数: 1個
   🏠 空室 1:
      部屋: 
      賃料: 145,100円
      間取り: 2LDK
      面積: 65㎡
      階数: 3階

🚫 空室なしの物件:
--------------------------------------------------
📍 亀戸二丁目: ご紹介出来るお部屋はございません。
📍 大島四丁目: ご紹介出来るお部屋はございません。
📍 大島六丁目: ご紹介出来るお部屋はございません。
📍 木場二丁目: ご紹介出来るお部屋はございません。
📍 大島七丁目: ご紹介出来るお部屋はございません。
📍 東陽パークサイドハイツ: ご紹介出来るお部屋はございません。
📍 木場公園三好住宅: ご紹介出来るお部屋はございません。
📍 木場公園平野住宅: ご紹介出来るお部屋はございません。
📍 木場三丁目パークハイツ: ご紹介出来るお部屋はございません。
📍 木場公園平野三丁目ハイツ: ご紹介出来るお部屋はございません。
📍 ヴェッセル木場南: ご紹介出来るお部屋はございません。
📍 シティコート大島: ご紹介出来るお部屋はございません。
📍 アーバンライフ亀戸: ご紹介出来るお部屋はございません。
📍 上馬二丁目: ご紹介出来るお部屋はございません。
📍 経堂赤堤通り: ご紹介出来るお部屋はございません。
📍 シティハイツ烏山: ご紹介出来るお部屋はございません。
📍 世田谷通りシティハイツ若林: ご紹介出来るお部屋はございません。
📍 フレール西経堂: ご紹介出来るお部屋はございません。
📍 スクエアー世田谷桜丘: ご紹介出来るお部屋はございません。
📍 アクティ三軒茶屋: ご紹介出来るお部屋はございません。
📍 シティコート上馬: ご紹介出来るお部屋はございません。
"""
        html_content = sender.format_text_results(test_results)
        subject = f"[テスト] {args.subject}"
        
    elif args.json:
        # JSONファイルから結果を読み込む
        results_data = load_results_from_json(args.json)
        if not results_data:
            print("❌ JSONファイルを読み込めないか、ファイルが空です")
            return
        
        html_content = sender.format_results_to_html(results_data)
        subject = args.subject
        
    elif args.text:
        # テキストファイルから結果を読み込む
        try:
            with open(args.text, 'r', encoding='utf-8') as f:
                text_results = f.read()
            html_content = sender.format_text_results(text_results)
            subject = args.subject
        except Exception as e:
            print(f"❌ テキストファイルの読み込みに失敗しました: {e}")
            return
    else:
        print("❌ --json、--text、または --test パラメータを指定してください")
        return
    
    # メールを送信
    success = sender.send_email(to_addr, subject, html_content)
    
    if success:
        print(f"\n🎉 メール送信完了！")
        print(f"📧 宛先: {to_addr}")
        print(f"📧 件名: {subject}")
    else:
        print(f"\n💥 メール送信失敗！")
        sys.exit(1)

if __name__ == "__main__":
    main()