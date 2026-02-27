const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const Database = require('better-sqlite3');
const { v4: uuidv4 } = require('uuid');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(helmet());
app.use(compression());
app.use(cors());
app.use(express.json());

// Database setup
const dbPath = process.env.DATABASE_PATH || path.join(__dirname, 'quantara_watch.db');
const db = new Database(dbPath);

// Initialize database tables
db.exec(`
  -- Users table
  CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    device_id TEXT UNIQUE,
    name TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_sync DATETIME
  );

  -- Biometric readings table
  CREATE TABLE IF NOT EXISTS biometrics (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    timestamp DATETIME NOT NULL,
    heart_rate INTEGER,
    hrv REAL,
    active_energy REAL,
    steps INTEGER,
    exercise_minutes INTEGER,
    min_heart_rate INTEGER,
    max_heart_rate INTEGER,
    avg_heart_rate INTEGER,
    wellness_score INTEGER,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id)
  );

  -- Daily summaries table
  CREATE TABLE IF NOT EXISTS daily_summaries (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    date DATE NOT NULL,
    avg_heart_rate INTEGER,
    avg_hrv REAL,
    total_steps INTEGER,
    total_calories REAL,
    total_exercise_minutes INTEGER,
    avg_wellness_score INTEGER,
    recovery_status TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id),
    UNIQUE(user_id, date)
  );

  -- Heart rate zones table
  CREATE TABLE IF NOT EXISTS heart_rate_zones (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    date DATE NOT NULL,
    resting_minutes INTEGER DEFAULT 0,
    normal_minutes INTEGER DEFAULT 0,
    elevated_minutes INTEGER DEFAULT 0,
    high_minutes INTEGER DEFAULT 0,
    max_minutes INTEGER DEFAULT 0,
    FOREIGN KEY (user_id) REFERENCES users(id),
    UNIQUE(user_id, date)
  );

  -- Breathing sessions table
  CREATE TABLE IF NOT EXISTS breathing_sessions (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    timestamp DATETIME NOT NULL,
    duration_seconds INTEGER,
    pre_heart_rate INTEGER,
    post_heart_rate INTEGER,
    FOREIGN KEY (user_id) REFERENCES users(id)
  );

  -- Create indexes
  CREATE INDEX IF NOT EXISTS idx_biometrics_user_timestamp ON biometrics(user_id, timestamp);
  CREATE INDEX IF NOT EXISTS idx_daily_summaries_user_date ON daily_summaries(user_id, date);
`);

console.log('Database initialized');

// ==================== API ROUTES ====================

// Health check
app.get('/', (req, res) => {
  res.json({
    service: 'Quantara Watch API',
    version: '1.0.0',
    status: 'healthy',
    timestamp: new Date().toISOString(),
    endpoints: {
      sync: 'POST /api/sync',
      biometrics: 'GET /api/biometrics/:userId',
      summary: 'GET /api/summary/:userId',
      trends: 'GET /api/trends/:userId',
      breathing: 'POST /api/breathing'
    }
  });
});

// ==================== USER MANAGEMENT ====================

// Register or get user by device ID
app.post('/api/users/register', (req, res) => {
  try {
    const { device_id, name } = req.body;

    if (!device_id) {
      return res.status(400).json({ error: 'device_id is required' });
    }

    // Check if user exists
    let user = db.prepare('SELECT * FROM users WHERE device_id = ?').get(device_id);

    if (!user) {
      const id = uuidv4();
      db.prepare('INSERT INTO users (id, device_id, name) VALUES (?, ?, ?)').run(id, device_id, name || 'Watch User');
      user = db.prepare('SELECT * FROM users WHERE id = ?').get(id);
    }

    res.json({ success: true, user });
  } catch (error) {
    console.error('Register error:', error);
    res.status(500).json({ error: error.message });
  }
});

// ==================== BIOMETRIC SYNC ====================

// Sync biometric data from Watch
app.post('/api/sync', (req, res) => {
  try {
    const {
      device_id,
      user_id,
      timestamp,
      heart_rate,
      hrv,
      active_energy,
      steps,
      exercise_minutes,
      min_heart_rate,
      max_heart_rate,
      avg_heart_rate,
      wellness_score
    } = req.body;

    // Get or create user
    let userId = user_id;
    if (!userId && device_id) {
      const user = db.prepare('SELECT id FROM users WHERE device_id = ?').get(device_id);
      if (user) {
        userId = user.id;
      } else {
        userId = uuidv4();
        db.prepare('INSERT INTO users (id, device_id) VALUES (?, ?)').run(userId, device_id);
      }
    }

    if (!userId) {
      return res.status(400).json({ error: 'user_id or device_id required' });
    }

    // Insert biometric reading
    const id = uuidv4();
    const readingTimestamp = timestamp || new Date().toISOString();

    db.prepare(`
      INSERT INTO biometrics (
        id, user_id, timestamp, heart_rate, hrv, active_energy,
        steps, exercise_minutes, min_heart_rate, max_heart_rate,
        avg_heart_rate, wellness_score
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      id, userId, readingTimestamp, heart_rate, hrv, active_energy,
      steps, exercise_minutes, min_heart_rate, max_heart_rate,
      avg_heart_rate, wellness_score
    );

    // Update user last sync
    db.prepare('UPDATE users SET last_sync = ? WHERE id = ?').run(new Date().toISOString(), userId);

    // Update daily summary
    updateDailySummary(userId, readingTimestamp);

    // Update heart rate zones
    if (heart_rate) {
      updateHeartRateZones(userId, heart_rate);
    }

    res.json({
      success: true,
      reading_id: id,
      user_id: userId,
      synced_at: new Date().toISOString()
    });
  } catch (error) {
    console.error('Sync error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Batch sync multiple readings
app.post('/api/sync/batch', (req, res) => {
  try {
    const { device_id, user_id, readings } = req.body;

    if (!readings || !Array.isArray(readings)) {
      return res.status(400).json({ error: 'readings array required' });
    }

    // Get or create user
    let userId = user_id;
    if (!userId && device_id) {
      const user = db.prepare('SELECT id FROM users WHERE device_id = ?').get(device_id);
      if (user) {
        userId = user.id;
      } else {
        userId = uuidv4();
        db.prepare('INSERT INTO users (id, device_id) VALUES (?, ?)').run(userId, device_id);
      }
    }

    const insertStmt = db.prepare(`
      INSERT INTO biometrics (
        id, user_id, timestamp, heart_rate, hrv, active_energy,
        steps, exercise_minutes, min_heart_rate, max_heart_rate,
        avg_heart_rate, wellness_score
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);

    const insertMany = db.transaction((readings) => {
      for (const r of readings) {
        insertStmt.run(
          uuidv4(), userId, r.timestamp || new Date().toISOString(),
          r.heart_rate, r.hrv, r.active_energy,
          r.steps, r.exercise_minutes, r.min_heart_rate,
          r.max_heart_rate, r.avg_heart_rate, r.wellness_score
        );
      }
    });

    insertMany(readings);

    // Update user last sync
    db.prepare('UPDATE users SET last_sync = ? WHERE id = ?').run(new Date().toISOString(), userId);

    res.json({
      success: true,
      synced_count: readings.length,
      user_id: userId
    });
  } catch (error) {
    console.error('Batch sync error:', error);
    res.status(500).json({ error: error.message });
  }
});

// ==================== DATA RETRIEVAL ====================

// Get recent biometrics
app.get('/api/biometrics/:userId', (req, res) => {
  try {
    const { userId } = req.params;
    const { limit = 100, since } = req.query;

    let query = 'SELECT * FROM biometrics WHERE user_id = ?';
    const params = [userId];

    if (since) {
      query += ' AND timestamp > ?';
      params.push(since);
    }

    query += ' ORDER BY timestamp DESC LIMIT ?';
    params.push(parseInt(limit));

    const readings = db.prepare(query).all(...params);
    res.json({ success: true, count: readings.length, readings });
  } catch (error) {
    console.error('Get biometrics error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Get latest reading
app.get('/api/biometrics/:userId/latest', (req, res) => {
  try {
    const { userId } = req.params;
    const reading = db.prepare(`
      SELECT * FROM biometrics WHERE user_id = ? ORDER BY timestamp DESC LIMIT 1
    `).get(userId);

    res.json({ success: true, reading });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get daily summary
app.get('/api/summary/:userId', (req, res) => {
  try {
    const { userId } = req.params;
    const { date } = req.query;

    const targetDate = date || new Date().toISOString().split('T')[0];

    const summary = db.prepare(`
      SELECT * FROM daily_summaries WHERE user_id = ? AND date = ?
    `).get(userId, targetDate);

    const zones = db.prepare(`
      SELECT * FROM heart_rate_zones WHERE user_id = ? AND date = ?
    `).get(userId, targetDate);

    res.json({
      success: true,
      date: targetDate,
      summary,
      heart_rate_zones: zones
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get weekly summaries
app.get('/api/summary/:userId/weekly', (req, res) => {
  try {
    const { userId } = req.params;

    const summaries = db.prepare(`
      SELECT * FROM daily_summaries
      WHERE user_id = ? AND date >= date('now', '-7 days')
      ORDER BY date DESC
    `).all(userId);

    res.json({ success: true, summaries });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get trends
app.get('/api/trends/:userId', (req, res) => {
  try {
    const { userId } = req.params;
    const { days = 7 } = req.query;

    // Heart rate trend
    const heartRateTrend = db.prepare(`
      SELECT
        date(timestamp) as date,
        AVG(heart_rate) as avg_hr,
        MIN(heart_rate) as min_hr,
        MAX(heart_rate) as max_hr
      FROM biometrics
      WHERE user_id = ? AND timestamp >= datetime('now', '-' || ? || ' days')
      GROUP BY date(timestamp)
      ORDER BY date
    `).all(userId, days);

    // HRV trend
    const hrvTrend = db.prepare(`
      SELECT
        date(timestamp) as date,
        AVG(hrv) as avg_hrv
      FROM biometrics
      WHERE user_id = ? AND hrv IS NOT NULL AND timestamp >= datetime('now', '-' || ? || ' days')
      GROUP BY date(timestamp)
      ORDER BY date
    `).all(userId, days);

    // Steps trend
    const stepsTrend = db.prepare(`
      SELECT
        date(timestamp) as date,
        MAX(steps) as total_steps
      FROM biometrics
      WHERE user_id = ? AND timestamp >= datetime('now', '-' || ? || ' days')
      GROUP BY date(timestamp)
      ORDER BY date
    `).all(userId, days);

    // Wellness score trend
    const wellnessTrend = db.prepare(`
      SELECT
        date(timestamp) as date,
        AVG(wellness_score) as avg_wellness
      FROM biometrics
      WHERE user_id = ? AND wellness_score IS NOT NULL AND timestamp >= datetime('now', '-' || ? || ' days')
      GROUP BY date(timestamp)
      ORDER BY date
    `).all(userId, days);

    res.json({
      success: true,
      days: parseInt(days),
      trends: {
        heart_rate: heartRateTrend,
        hrv: hrvTrend,
        steps: stepsTrend,
        wellness: wellnessTrend
      }
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// ==================== BREATHING SESSIONS ====================

app.post('/api/breathing', (req, res) => {
  try {
    const { user_id, device_id, duration_seconds, pre_heart_rate, post_heart_rate } = req.body;

    let userId = user_id;
    if (!userId && device_id) {
      const user = db.prepare('SELECT id FROM users WHERE device_id = ?').get(device_id);
      if (user) userId = user.id;
    }

    if (!userId) {
      return res.status(400).json({ error: 'user_id or device_id required' });
    }

    const id = uuidv4();
    db.prepare(`
      INSERT INTO breathing_sessions (id, user_id, timestamp, duration_seconds, pre_heart_rate, post_heart_rate)
      VALUES (?, ?, ?, ?, ?, ?)
    `).run(id, userId, new Date().toISOString(), duration_seconds, pre_heart_rate, post_heart_rate);

    res.json({
      success: true,
      session_id: id,
      heart_rate_change: post_heart_rate && pre_heart_rate ? post_heart_rate - pre_heart_rate : null
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get breathing history
app.get('/api/breathing/:userId', (req, res) => {
  try {
    const { userId } = req.params;
    const { limit = 30 } = req.query;

    const sessions = db.prepare(`
      SELECT * FROM breathing_sessions
      WHERE user_id = ?
      ORDER BY timestamp DESC
      LIMIT ?
    `).all(userId, parseInt(limit));

    res.json({ success: true, sessions });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// ==================== ANALYTICS ====================

// Get insights
app.get('/api/insights/:userId', (req, res) => {
  try {
    const { userId } = req.params;

    // Get recent data
    const recentReadings = db.prepare(`
      SELECT * FROM biometrics
      WHERE user_id = ?
      ORDER BY timestamp DESC
      LIMIT 100
    `).all(userId);

    if (recentReadings.length === 0) {
      return res.json({ success: true, insights: [] });
    }

    const insights = [];

    // Average HRV analysis
    const avgHrv = recentReadings.reduce((sum, r) => sum + (r.hrv || 0), 0) / recentReadings.length;
    if (avgHrv > 60) {
      insights.push({
        type: 'positive',
        category: 'recovery',
        message: 'Excellent HRV! Your recovery is optimal.',
        value: Math.round(avgHrv)
      });
    } else if (avgHrv < 30) {
      insights.push({
        type: 'attention',
        category: 'recovery',
        message: 'Low HRV detected. Consider prioritizing rest.',
        value: Math.round(avgHrv)
      });
    }

    // Resting heart rate analysis
    const restingReadings = recentReadings.filter(r => r.heart_rate && r.heart_rate < 70);
    if (restingReadings.length > 0) {
      const avgResting = restingReadings.reduce((sum, r) => sum + r.heart_rate, 0) / restingReadings.length;
      if (avgResting < 60) {
        insights.push({
          type: 'positive',
          category: 'fitness',
          message: 'Great resting heart rate indicates good cardiovascular fitness.',
          value: Math.round(avgResting)
        });
      }
    }

    // Step goal analysis
    const todaySteps = recentReadings[0]?.steps || 0;
    if (todaySteps >= 10000) {
      insights.push({
        type: 'achievement',
        category: 'activity',
        message: 'Step goal achieved! Keep up the great work.',
        value: todaySteps
      });
    }

    res.json({ success: true, insights });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// ==================== HELPER FUNCTIONS ====================

function updateDailySummary(userId, timestamp) {
  const date = timestamp.split('T')[0];

  const stats = db.prepare(`
    SELECT
      AVG(heart_rate) as avg_heart_rate,
      AVG(hrv) as avg_hrv,
      MAX(steps) as total_steps,
      MAX(active_energy) as total_calories,
      MAX(exercise_minutes) as total_exercise_minutes,
      AVG(wellness_score) as avg_wellness_score
    FROM biometrics
    WHERE user_id = ? AND date(timestamp) = ?
  `).get(userId, date);

  if (!stats) return;

  // Determine recovery status based on HRV
  let recoveryStatus = 'unknown';
  if (stats.avg_hrv) {
    if (stats.avg_hrv > 65) recoveryStatus = 'excellent';
    else if (stats.avg_hrv > 50) recoveryStatus = 'good';
    else if (stats.avg_hrv > 35) recoveryStatus = 'moderate';
    else recoveryStatus = 'low';
  }

  db.prepare(`
    INSERT INTO daily_summaries (
      id, user_id, date, avg_heart_rate, avg_hrv, total_steps,
      total_calories, total_exercise_minutes, avg_wellness_score, recovery_status
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(user_id, date) DO UPDATE SET
      avg_heart_rate = excluded.avg_heart_rate,
      avg_hrv = excluded.avg_hrv,
      total_steps = excluded.total_steps,
      total_calories = excluded.total_calories,
      total_exercise_minutes = excluded.total_exercise_minutes,
      avg_wellness_score = excluded.avg_wellness_score,
      recovery_status = excluded.recovery_status
  `).run(
    uuidv4(), userId, date,
    Math.round(stats.avg_heart_rate),
    stats.avg_hrv,
    stats.total_steps,
    stats.total_calories,
    stats.total_exercise_minutes,
    Math.round(stats.avg_wellness_score || 0),
    recoveryStatus
  );
}

function updateHeartRateZones(userId, heartRate) {
  const date = new Date().toISOString().split('T')[0];

  // Ensure row exists
  db.prepare(`
    INSERT OR IGNORE INTO heart_rate_zones (id, user_id, date)
    VALUES (?, ?, ?)
  `).run(uuidv4(), userId, date);

  // Determine zone and update
  let zoneColumn;
  if (heartRate < 60) zoneColumn = 'resting_minutes';
  else if (heartRate < 100) zoneColumn = 'normal_minutes';
  else if (heartRate < 140) zoneColumn = 'elevated_minutes';
  else if (heartRate < 170) zoneColumn = 'high_minutes';
  else zoneColumn = 'max_minutes';

  db.prepare(`
    UPDATE heart_rate_zones
    SET ${zoneColumn} = ${zoneColumn} + 1
    WHERE user_id = ? AND date = ?
  `).run(userId, date);
}

// ==================== START SERVER ====================

app.listen(PORT, '0.0.0.0', () => {
  console.log(`
╔═══════════════════════════════════════════════════════════╗
║          🧠 Quantara Watch API - Running                  ║
╠═══════════════════════════════════════════════════════════╣
║  Port: ${PORT}                                              ║
║  Database: SQLite                                         ║
║  Status: Ready for biometric sync                         ║
╚═══════════════════════════════════════════════════════════╝
  `);
});

module.exports = app;
