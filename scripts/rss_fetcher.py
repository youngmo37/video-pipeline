#!/usr/bin/env python3
import feedparser
import psycopg2
import sys
from datetime import datetime

DB_CONFIG = {
    'host': 'localhost',
    'database': 'video_pipeline',
    'user': 'n8n',
    'password': 'n8n123',
    'port': 5432
}

def get_connection():
    return psycopg2.connect(**DB_CONFIG)

def fetch_rss_feeds():
    conn = get_connection()
    cur = conn.cursor()
    
    cur.execute("SELECT id, name, url, category FROM rss_sources WHERE enabled = true")
    sources = cur.fetchall()
    
    new_topics = 0
    for source_id, name, url, category in sources:
        print(f"📡 Fetching: {name}")
        try:
            feed = feedparser.parse(url)
            
            for entry in feed.entries[:5]:  # 최근 5개만
                title = entry.title
                
                # 중복 확인
                cur.execute("SELECT id FROM content_plan WHERE keyword = %s", (title,))
                if cur.fetchone():
                    continue
                
                cur.execute("""
                    INSERT INTO content_plan (keyword, target_age, format, voice_tone, status, category)
                    VALUES (%s, '전연령', 'shorts', 'professional', 'planning', %s)
                """, (title, category))
                new_topics += 1
            
            cur.execute("UPDATE rss_sources SET last_fetched = NOW() WHERE id = %s", (source_id,))
        except Exception as e:
            print(f"  ⚠️  오류: {e}")
    
    conn.commit()
    conn.close()
    print(f"\n✅ {new_topics}개 새 주제 추가됨")

if __name__ == "__main__":
    fetch_rss_feeds()
