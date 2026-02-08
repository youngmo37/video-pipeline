#!/usr/bin/env python3
import psycopg2
import sys
from datetime import datetime
import random

DB_CONFIG = {
    'host': 'localhost',
    'database': 'video_pipeline',
    'user': 'n8n',
    'password': 'n8n123',
    'port': 5432
}

def get_connection():
    return psycopg2.connect(**DB_CONFIG)

def list_topics(status='all'):
    conn = get_connection()
    cur = conn.cursor()
    
    if status == 'all':
        cur.execute("SELECT id, keyword, target_age, status, category, created_at FROM content_plan ORDER BY created_at DESC LIMIT 20")
    else:
        cur.execute("SELECT id, keyword, target_age, status, category, created_at FROM content_plan WHERE status = %s ORDER BY created_at DESC", (status,))
    
    rows = cur.fetchall()
    conn.close()
    
    print(f"\n{'ID':<5} {'주제':<40} {'연령':<10} {'상태':<12} {'카테고리':<10}")
    print("-" * 80)
    for row in rows:
        print(f"{row[0]:<5} {row[1]:<40} {row[2]:<10} {row[3]:<12} {row[4] or 'N/A':<10}")
    print(f"\n총 {len(rows)}개 주제")

def generate_from_template():
    conn = get_connection()
    cur = conn.cursor()
    
    cur.execute("""
        SELECT id, template, target_age, category
        FROM topic_templates
        WHERE enabled = true AND (last_used IS NULL OR last_used < NOW() - INTERVAL '7 days')
        ORDER BY RANDOM() * weight DESC LIMIT 1
    """)
    
    template = cur.fetchone()
    if not template:
        print("사용 가능한 템플릿이 없습니다.")
        conn.close()
        return
    
    template_id, text, age, category = template
    filled = text
    
    cur.execute("""
        INSERT INTO content_plan (keyword, target_age, format, voice_tone, status, category)
        VALUES (%s, %s, 'shorts', 'professional', 'planning', %s)
        RETURNING id
    """, (filled, age, category))
    
    new_id = cur.fetchone()[0]
    cur.execute("UPDATE topic_templates SET last_used = NOW() WHERE id = %s", (template_id,))
    
    conn.commit()
    conn.close()
    
    print(f"\n✅ 새 주제 생성 (ID: {new_id}): {filled}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("사용법: python3 topic_manager.py [list|generate]")
        sys.exit(1)
    
    if sys.argv[1] == 'list':
        status = sys.argv[2] if len(sys.argv) > 2 else 'all'
        list_topics(status)
    elif sys.argv[1] == 'generate':
        generate_from_template()
