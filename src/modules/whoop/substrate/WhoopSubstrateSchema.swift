import Foundation

public enum WhoopSubstrateSchema {
    public static let ddl: String = """
        CREATE TABLE IF NOT EXISTS decoded_onehz (
            device_id TEXT NOT NULL DEFAULT '',
            ts_ms INTEGER NOT NULL DEFAULT 0,
            rec_ts INTEGER,
            counter INTEGER NOT NULL,
            hr INTEGER,
            ax REAL,
            ay REAL,
            az REAL,
            spo2_red_raw INTEGER,
            spo2_ir_raw INTEGER,
            skin_temp_raw INTEGER,
            step_count INTEGER,
            step_cadence INTEGER,
            activity_class INTEGER,
            skin_temp_c REAL,
            on_wrist INTEGER,
            hr_valid INTEGER,
            hr_alt INTEGER,
            ambient_raw INTEGER,
            device_family TEXT,
            source TEXT,
            temp_ch2_c REAL,
            temp_ch3_c REAL,
            signal_quality_logvar REAL,
            dyn_accel_g REAL,
            ts_subsec INTEGER,
            band_sleep_state INTEGER,
            PRIMARY KEY (device_id, ts_ms)
        );
        CREATE INDEX IF NOT EXISTS idx_decoded_onehz_rects ON decoded_onehz(rec_ts, counter);

        CREATE TABLE IF NOT EXISTS decoded_rr (
            device_id TEXT NOT NULL DEFAULT '',
            ts_ms INTEGER NOT NULL DEFAULT 0,
            rec_ts INTEGER NOT NULL,
            beat_index INTEGER NOT NULL,
            rr_ts_ms INTEGER NOT NULL DEFAULT 0,
            rr_ms INTEGER NOT NULL,
            device_family TEXT,
            source TEXT,
            beat_ts_ms INTEGER,
            PRIMARY KEY (device_id, ts_ms, beat_index)
        );
        CREATE INDEX IF NOT EXISTS idx_decoded_rr_rects ON decoded_rr(rec_ts, beat_index);

        CREATE TABLE IF NOT EXISTS live_coverage (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            start_ts INTEGER NOT NULL,
            end_ts INTEGER NOT NULL,
            steps INTEGER NOT NULL,
            day TEXT NOT NULL,
            source TEXT NOT NULL DEFAULT 'band',
            device_id TEXT NOT NULL DEFAULT ''
        );
        CREATE INDEX IF NOT EXISTS idx_live_coverage_day ON live_coverage(day);

        CREATE TABLE IF NOT EXISTS raw_archive_frames (
            device_id TEXT NOT NULL DEFAULT '',
            hash BLOB NOT NULL,
            counter INTEGER,
            packet_type INTEGER NOT NULL,
            rec_ts INTEGER,
            captured_at INTEGER NOT NULL,
            reason TEXT NOT NULL,
            hex TEXT,
            frame BLOB,
            UNIQUE (device_id, hash)
        );
        CREATE INDEX IF NOT EXISTS idx_raw_archive_captured ON raw_archive_frames(captured_at DESC);
        CREATE INDEX IF NOT EXISTS idx_raw_archive_reason ON raw_archive_frames(reason, device_id);

        CREATE TABLE IF NOT EXISTS band_battery (
            device_id TEXT NOT NULL DEFAULT '',
            ts INTEGER NOT NULL,
            battery_pct REAL,
            charging INTEGER,
            wrist_on INTEGER,
            millivolts INTEGER,
            charge_units INTEGER,
            source TEXT NOT NULL,
            PRIMARY KEY (device_id, ts, source)
        );
        CREATE INDEX IF NOT EXISTS idx_band_battery_ts ON band_battery(ts DESC);

        CREATE TABLE IF NOT EXISTS band_backlog (
            device_id TEXT NOT NULL DEFAULT '',
            ts INTEGER NOT NULL,
            written INTEGER,
            used INTEGER,
            capacity INTEGER,
            trim_page INTEGER,
            wrap_count INTEGER,
            free_records INTEGER,
            device_family TEXT,
            PRIMARY KEY (device_id, ts)
        );

        CREATE TABLE IF NOT EXISTS band_events (
            device_id TEXT NOT NULL DEFAULT '',
            hex TEXT NOT NULL,
            event_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            ts INTEGER NOT NULL,
            payload_json TEXT NOT NULL DEFAULT '{}',
            captured_at INTEGER NOT NULL,
            PRIMARY KEY (device_id, hex)
        );
        CREATE INDEX IF NOT EXISTS idx_band_events_ts ON band_events(ts, event_id);

        CREATE TABLE IF NOT EXISTS events (
            device_id TEXT NOT NULL DEFAULT '',
            hex TEXT NOT NULL,
            event_id INTEGER,
            ts INTEGER,
            captured_at INTEGER NOT NULL,
            PRIMARY KEY (device_id, hex)
        );
        CREATE INDEX IF NOT EXISTS idx_events_ts ON events(ts);

        CREATE TABLE IF NOT EXISTS sync_cursor (
            name TEXT PRIMARY KEY,
            value TEXT,
            updated_at INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS samples (
            device_id TEXT NOT NULL DEFAULT '',
            ts INTEGER NOT NULL DEFAULT 0,
            counter INTEGER NOT NULL DEFAULT 0,
            hr INTEGER,
            rr_ms TEXT,
            hex TEXT,
            PRIMARY KEY (device_id, ts, counter)
        );

        CREATE TABLE IF NOT EXISTS ecg_reading (
            id TEXT PRIMARY KEY,
            device_id TEXT NOT NULL,
            source TEXT NOT NULL,
            wrist TEXT NOT NULL,
            start_ts INTEGER NOT NULL,
            end_ts INTEGER NOT NULL,
            strap_terminal_ts INTEGER,
            strap_terminal_subsec INTEGER,
            result_code INTEGER NOT NULL,
            category TEXT NOT NULL,
            avg_hr INTEGER,
            quality INTEGER,
            unreadable_mask INTEGER NOT NULL DEFAULT 0,
            interruptions INTEGER NOT NULL DEFAULT 0,
            sample_rate_hz INTEGER NOT NULL DEFAULT 100,
            sample_unit TEXT NOT NULL DEFAULT 'filtered_input_referred_uv',
            sample_count INTEGER NOT NULL,
            min_uv INTEGER,
            max_uv INTEGER,
            rms_uv REAL,
            missing_segments INTEGER NOT NULL DEFAULT 0,
            status TEXT NOT NULL,
            notes TEXT,
            created_at INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS ecg_reading_packet (
            reading_id TEXT NOT NULL,
            ordinal INTEGER NOT NULL,
            sequence INTEGER NOT NULL,
            strap_seconds INTEGER,
            strap_subsec INTEGER,
            sample_count INTEGER NOT NULL,
            samples BLOB NOT NULL,
            inner_hex TEXT NOT NULL,
            is_placeholder INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (reading_id, ordinal)
        );

        CREATE TABLE IF NOT EXISTS ecg_raw_packet (
            hex TEXT PRIMARY KEY,
            device_id TEXT NOT NULL,
            sequence INTEGER,
            strap_seconds INTEGER,
            strap_subsec INTEGER,
            captured_at INTEGER NOT NULL,
            reading_id TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_ecg_raw_packet_strap ON ecg_raw_packet(strap_seconds);

        CREATE TABLE IF NOT EXISTS baselines (
            key TEXT PRIMARY KEY,
            payload_json TEXT NOT NULL,
            updated_at INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS metric_series (
            date TEXT NOT NULL,
            key TEXT NOT NULL,
            value REAL,
            PRIMARY KEY (date, key)
        );

        CREATE TABLE IF NOT EXISTS day_result (
            day_id TEXT NOT NULL,
            algo_version INTEGER NOT NULL,
            payload_json TEXT NOT NULL,
            window_json TEXT NOT NULL DEFAULT '{}',
            computed_at INTEGER NOT NULL,
            finalized INTEGER NOT NULL DEFAULT 0,
            rhr REAL,
            rmssd REAL,
            readiness REAL,
            skipped INTEGER NOT NULL DEFAULT 0,
            partial INTEGER NOT NULL DEFAULT 0,
            imported INTEGER NOT NULL DEFAULT 0,
            source TEXT,
            device_family TEXT,
            PRIMARY KEY (day_id, algo_version)
        );

        CREATE TABLE IF NOT EXISTS cycle_log (
            date TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            note TEXT
        );

        CREATE TABLE IF NOT EXISTS workout_suggestions (
            id TEXT PRIMARY KEY,
            date TEXT NOT NULL,
            start_ts INTEGER NOT NULL,
            end_ts INTEGER NOT NULL,
            avg_bpm INTEGER,
            peak_bpm INTEGER,
            duration_min INTEGER,
            sport TEXT,
            dismissed INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS sleep_override (
            day_id TEXT PRIMARY KEY,
            onset_ts INTEGER NOT NULL,
            offset_ts INTEGER NOT NULL,
            source TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            note TEXT,
            stages_json TEXT
        );

        CREATE TABLE IF NOT EXISTS breathing_session (
            started_at INTEGER PRIMARY KEY,
            ended_at   INTEGER NOT NULL,
            pattern    TEXT NOT NULL,
            seconds    INTEGER NOT NULL,
            coherence  REAL,
            confidence REAL,
            pre_rmssd  REAL,
            post_rmssd REAL
        );

        CREATE TABLE IF NOT EXISTS sleep_nap (
            day_id TEXT NOT NULL,
            start_ts INTEGER NOT NULL,
            end_ts INTEGER NOT NULL,
            source TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            payload_json TEXT,
            PRIMARY KEY (day_id, start_ts)
        );

        CREATE TABLE IF NOT EXISTS activity_suggestions (
            id TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            day_id TEXT NOT NULL,
            start_ts INTEGER NOT NULL,
            end_ts INTEGER NOT NULL,
            detection_start INTEGER NOT NULL,
            detection_end INTEGER NOT NULL,
            details_json TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            revision INTEGER NOT NULL DEFAULT 0,
            linked_id TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS activity_pending ON activity_suggestions(status, start_ts);
        """

    public static func apply(to db: Database) throws {
        if db.path != ":memory:" {
            _ = try? db.query("PRAGMA journal_mode = WAL")
        }
        try db.runScript(ddl)

        let oneHzCols = Set(try db.query("PRAGMA table_info(decoded_onehz)").map { $0.text("name") })
        for (col, spec) in [
            ("skin_temp_c", "REAL"),
            ("temp_ch2_c", "REAL"),
            ("temp_ch3_c", "REAL"),
            ("signal_quality_logvar", "REAL"),
            ("dyn_accel_g", "REAL"),
            ("ts_subsec", "INTEGER"),
            ("band_sleep_state", "INTEGER"),
        ] where !oneHzCols.contains(col) {
            try db.execute("ALTER TABLE decoded_onehz ADD COLUMN \(col) \(spec)")
        }

        let rrCols = Set(try db.query("PRAGMA table_info(decoded_rr)").map { $0.text("name") })
        if !rrCols.contains("beat_ts_ms") {
            try db.execute("ALTER TABLE decoded_rr ADD COLUMN beat_ts_ms INTEGER")
        }

        let ovCols = Set(try db.query("PRAGMA table_info(sleep_override)").map { $0.text("name") })
        if !ovCols.contains("note") {
            try db.execute("ALTER TABLE sleep_override ADD COLUMN note TEXT")
        }
        if !ovCols.contains("stages_json") {
            try db.execute("ALTER TABLE sleep_override ADD COLUMN stages_json TEXT")
        }

        let drCols = Set(try db.query("PRAGMA table_info(day_result)").map { $0.text("name") })
        for (col, spec) in [
            ("source", "TEXT"),
            ("device_family", "TEXT"),
            ("window_json", "TEXT NOT NULL DEFAULT '{}'"),
            ("rhr", "REAL"),
            ("rmssd", "REAL"),
            ("readiness", "REAL"),
            ("skipped", "INTEGER NOT NULL DEFAULT 0"),
            ("imported", "INTEGER NOT NULL DEFAULT 0"),
        ] where !drCols.contains(col) {
            try db.execute("ALTER TABLE day_result ADD COLUMN \(col) \(spec)")
        }
    }
}
