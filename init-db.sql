CREATE TABLE IF NOT EXISTS content_plan (
    id SERIAL PRIMARY KEY,
    target_age VARCHAR(50),
    keyword VARCHAR(200) NOT NULL,
    format VARCHAR(20) DEFAULT 'shorts',
    voice_tone VARCHAR(50) DEFAULT 'professional',
    status VARCHAR(50) DEFAULT 'planning',
    title TEXT,
    description TEXT,
    script TEXT,
    tags TEXT[],
    category VARCHAR(100),
    audio_url TEXT,
    video_url TEXT,
    youtube_id VARCHAR(100),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS scenes (
    id SERIAL PRIMARY KEY,
    content_id INTEGER REFERENCES content_plan(id) ON DELETE CASCADE,
    scene_number INTEGER NOT NULL,
    start_time FLOAT,
    end_time FLOAT,
    text TEXT,
    image_prompt TEXT,
    image_url TEXT,
    video_url TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS topic_templates (
    id SERIAL PRIMARY KEY,
    category VARCHAR(100) NOT NULL,
    template TEXT NOT NULL,
    target_age VARCHAR(50),
    tags TEXT[],
    weight INTEGER DEFAULT 1,
    last_used TIMESTAMP,
    enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS rss_sources (
    id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    url TEXT NOT NULL,
    category VARCHAR(100),
    enabled BOOLEAN DEFAULT true,
    last_fetched TIMESTAMP,
    fetch_interval INTEGER DEFAULT 3600,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_content_status ON content_plan(status);
CREATE INDEX idx_scenes_content ON scenes(content_id);
CREATE INDEX idx_rss_enabled ON rss_sources(enabled);

INSERT INTO topic_templates (category, template, target_age, tags, weight) VALUES
('기술', '2025년 주목해야 할 AI 기술 트렌드', '20-40대', ARRAY['AI', '기술'], 3),
('생활', '바쁜 직장인을 위한 아침 루틴', '20-30대', ARRAY['생산성', '라이프'], 5),
('건강', '겨울철 면역력 높이는 방법', '전연령', ARRAY['건강', '웰빙'], 3),
('재테크', '2025년 주목할 투자 트렌드', '30-40대', ARRAY['재테크', '투자'], 2);

INSERT INTO content_plan (target_age, keyword, format, voice_tone, status, category) VALUES
('20-30대', 'AI 도구로 업무 효율 2배 높이기', 'shorts', 'professional', 'planning', '기술'),
('전연령', '겨울 감기 예방 필수 팁 5가지', 'shorts', 'friendly', 'planning', '건강');

INSERT INTO rss_sources (name, url, category, enabled) VALUES
('TechCrunch', 'https://techcrunch.com/feed/', '기술', true),
('Hacker News', 'https://news.ycombinator.com/rss', '기술', true),
('The Verge', 'https://www.theverge.com/rss/index.xml', '기술', true);

CREATE OR REPLACE FUNCTION update_modified_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_content_plan_modtime
    BEFORE UPDATE ON content_plan
    FOR EACH ROW
    EXECUTE FUNCTION update_modified_column();
