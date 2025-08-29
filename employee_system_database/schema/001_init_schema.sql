-- Employee Performance & Management System - MySQL Schema
-- Version: 001_init_schema
-- Note: No seed data is included.

-- Ensure database exists (created by startup.sh), use it explicitly
-- CREATE DATABASE IF NOT EXISTS myapp;
-- USE myapp;

-- Set sane defaults for charsets/collation
SET NAMES utf8mb4;
SET CHARACTER SET utf8mb4;
SET collation_connection = 'utf8mb4_unicode_ci';

-- Enable InnoDB and FK checks safety toggles around apply
SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0;
SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0;

-- ROLES
CREATE TABLE IF NOT EXISTS roles (
    id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    name            VARCHAR(50) NOT NULL, -- e.g., super_admin, manager, team_lead, employee
    description     VARCHAR(255) NULL,
    is_system       TINYINT(1) NOT NULL DEFAULT 0, -- protected roles
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_roles_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Role-based access control roles';

-- USERS
CREATE TABLE IF NOT EXISTS users (
    id                  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    email               VARCHAR(190) NOT NULL,
    password_hash       VARCHAR(255) NOT NULL,
    first_name          VARCHAR(100) NOT NULL,
    last_name           VARCHAR(100) NOT NULL,
    phone               VARCHAR(30) NULL,
    status              ENUM('active','inactive','suspended') NOT NULL DEFAULT 'active',
    role_id             BIGINT UNSIGNED NOT NULL,
    manager_id          BIGINT UNSIGNED NULL, -- self-referencing manager
    avatar_url          VARCHAR(300) NULL,
    address_line1       VARCHAR(150) NULL,
    address_line2       VARCHAR(150) NULL,
    city                VARCHAR(100) NULL,
    state               VARCHAR(100) NULL,
    country             VARCHAR(100) NULL,
    postal_code         VARCHAR(20) NULL,
    timezone            VARCHAR(64) NULL,
    last_login_at       DATETIME NULL,
    created_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_users_email (email),
    KEY idx_users_role (role_id),
    KEY idx_users_manager (manager_id),
    CONSTRAINT fk_users_role FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_users_manager FOREIGN KEY (manager_id) REFERENCES users(id) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Application users with RBAC';

-- USER_ROLES (optional many-to-many if needed later, kept for flexibility; currently users.role_id handles primary role)
CREATE TABLE IF NOT EXISTS user_roles (
    user_id     BIGINT UNSIGNED NOT NULL,
    role_id     BIGINT UNSIGNED NOT NULL,
    assigned_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, role_id),
    CONSTRAINT fk_user_roles_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_user_roles_role FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Optional additional roles per user';

-- SCHEDULES (work schedule templates per user)
CREATE TABLE IF NOT EXISTS schedules (
    id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id         BIGINT UNSIGNED NOT NULL,
    name            VARCHAR(120) NOT NULL, -- e.g., Standard 9-5
    weekday         TINYINT UNSIGNED NOT NULL, -- 1=Mon .. 7=Sun
    start_time      TIME NOT NULL,
    end_time        TIME NOT NULL,
    is_flexible     TINYINT(1) NOT NULL DEFAULT 0,
    location_policy ENUM('onsite','remote','hybrid') NOT NULL DEFAULT 'hybrid',
    effective_from  DATE NOT NULL,
    effective_to    DATE NULL,
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_schedules_user (user_id),
    KEY idx_schedules_effective (effective_from, effective_to),
    CONSTRAINT fk_schedules_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE ON UPDATE CASCADE,
    CHECK (weekday BETWEEN 1 AND 7)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Recurring schedules per user by weekday';

-- BREAKS within schedules
CREATE TABLE IF NOT EXISTS breaks (
    id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    schedule_id     BIGINT UNSIGNED NOT NULL,
    name            VARCHAR(120) NOT NULL, -- e.g., Lunch
    start_time      TIME NOT NULL,
    end_time        TIME NOT NULL,
    is_paid         TINYINT(1) NOT NULL DEFAULT 0,
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_breaks_schedule (schedule_id),
    CONSTRAINT fk_breaks_schedule FOREIGN KEY (schedule_id) REFERENCES schedules(id) ON DELETE CASCADE ON UPDATE CASCADE,
    CHECK (start_time < end_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Break windows tied to schedules';

-- ATTENDANCE (supporting face/GPS/manual entry types)
CREATE TABLE IF NOT EXISTS attendance (
    id                  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id             BIGINT UNSIGNED NOT NULL,
    attendance_date     DATE NOT NULL,
    check_in_time       DATETIME NULL,
    check_out_time      DATETIME NULL,
    source              ENUM('face','gps','manual') NOT NULL,
    confidence_score    DECIMAL(5,2) NULL, -- for face recognition or model certainty
    gps_latitude        DECIMAL(10,7) NULL,
    gps_longitude       DECIMAL(10,7) NULL,
    gps_accuracy_m      DECIMAL(6,2) NULL,
    device_id           VARCHAR(120) NULL,
    notes               VARCHAR(500) NULL,
    is_late             TINYINT(1) NOT NULL DEFAULT 0,
    is_early_leave      TINYINT(1) NOT NULL DEFAULT 0,
    total_work_seconds  INT UNSIGNED NULL, -- can be computed or stored
    created_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_attendance_user_day (user_id, attendance_date),
    KEY idx_attendance_user_date (user_id, attendance_date),
    KEY idx_attendance_source (source),
    CONSTRAINT fk_attendance_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE ON UPDATE CASCADE,
    CHECK (source in ('face','gps','manual'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Daily attendance with modality and optional GPS/biometric metadata';

-- ATTENDANCE_EVENTS (detailed punch logs)
CREATE TABLE IF NOT EXISTS attendance_events (
    id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    attendance_id   BIGINT UNSIGNED NOT NULL,
    event_type      ENUM('check_in','check_out','break_start','break_end') NOT NULL,
    occurred_at     DATETIME NOT NULL,
    source          ENUM('face','gps','manual','system') NOT NULL DEFAULT 'system',
    gps_latitude    DECIMAL(10,7) NULL,
    gps_longitude   DECIMAL(10,7) NULL,
    device_id       VARCHAR(120) NULL,
    notes           VARCHAR(500) NULL,
    PRIMARY KEY (id),
    KEY idx_attendance_events_attendance (attendance_id),
    KEY idx_attendance_events_time (occurred_at),
    CONSTRAINT fk_attendance_events_attendance FOREIGN KEY (attendance_id) REFERENCES attendance(id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Fine-grained attendance events';

-- MEETINGS
CREATE TABLE IF NOT EXISTS meetings (
    id                  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    organizer_id        BIGINT UNSIGNED NOT NULL,
    title               VARCHAR(200) NOT NULL,
    description         TEXT NULL,
    start_time          DATETIME NOT NULL,
    end_time            DATETIME NOT NULL,
    location            VARCHAR(200) NULL,
    meeting_link        VARCHAR(300) NULL, -- for virtual
    status              ENUM('scheduled','cancelled','completed') NOT NULL DEFAULT 'scheduled',
    recurrence_rule     VARCHAR(300) NULL, -- iCal RRULE text if any
    created_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_meetings_org (organizer_id),
    KEY idx_meetings_time (start_time, end_time),
    CONSTRAINT fk_meetings_organizer FOREIGN KEY (organizer_id) REFERENCES users(id) ON DELETE CASCADE ON UPDATE CASCADE,
    CHECK (start_time < end_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Meetings scheduling with recurrence support';

CREATE TABLE IF NOT EXISTS meeting_participants (
    meeting_id      BIGINT UNSIGNED NOT NULL,
    user_id         BIGINT UNSIGNED NOT NULL,
    role            ENUM('required','optional') NOT NULL DEFAULT 'required',
    response        ENUM('none','accepted','declined','tentative') NOT NULL DEFAULT 'none',
    checked_in_at   DATETIME NULL,
    PRIMARY KEY (meeting_id, user_id),
    KEY idx_meeting_participants_user (user_id),
    CONSTRAINT fk_meeting_participants_meeting FOREIGN KEY (meeting_id) REFERENCES meetings(id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_meeting_participants_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Meeting participants with RSVP status';

-- TASKS and PROJECTS
CREATE TABLE IF NOT EXISTS projects (
    id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    name            VARCHAR(200) NOT NULL,
    description     TEXT NULL,
    owner_id        BIGINT UNSIGNED NOT NULL,
    status          ENUM('active','archived') NOT NULL DEFAULT 'active',
    start_date      DATE NULL,
    end_date        DATE NULL,
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_projects_owner (owner_id),
    CONSTRAINT fk_projects_owner FOREIGN KEY (owner_id) REFERENCES users(id) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Projects grouping tasks';

CREATE TABLE IF NOT EXISTS tasks (
    id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    project_id      BIGINT UNSIGNED NULL,
    title           VARCHAR(200) NOT NULL,
    description     TEXT NULL,
    status          ENUM('todo','in_progress','blocked','done','archived') NOT NULL DEFAULT 'todo',
    priority        ENUM('low','medium','high','urgent') NOT NULL DEFAULT 'medium',
    reporter_id     BIGINT UNSIGNED NOT NULL,
    assignee_id     BIGINT UNSIGNED NULL,
    start_date      DATE NULL,
    due_date        DATE NULL,
    completed_at    DATETIME NULL,
    estimated_hours DECIMAL(6,2) NULL,
    actual_hours    DECIMAL(6,2) NULL,
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_tasks_project (project_id),
    KEY idx_tasks_assignee (assignee_id),
    KEY idx_tasks_status (status),
    CONSTRAINT fk_tasks_project FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT fk_tasks_reporter FOREIGN KEY (reporter_id) REFERENCES users(id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_tasks_assignee FOREIGN KEY (assignee_id) REFERENCES users(id) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Task tracking with workflow and ownership';

CREATE TABLE IF NOT EXISTS task_comments (
    id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    task_id         BIGINT UNSIGNED NOT NULL,
    user_id         BIGINT UNSIGNED NOT NULL,
    comment         TEXT NOT NULL,
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_task_comments_task (task_id),
    KEY idx_task_comments_user (user_id),
    CONSTRAINT fk_task_comments_task FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_task_comments_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Comments on tasks';

CREATE TABLE IF NOT EXISTS task_attachments (
    id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    task_id         BIGINT UNSIGNED NOT NULL,
    uploaded_by     BIGINT UNSIGNED NOT NULL,
    file_name       VARCHAR(255) NOT NULL,
    file_url        VARCHAR(500) NOT NULL,
    file_size_bytes BIGINT UNSIGNED NULL,
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_task_attachments_task (task_id),
    CONSTRAINT fk_task_attachments_task FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_task_attachments_user FOREIGN KEY (uploaded_by) REFERENCES users(id) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Attachments associated with tasks';

-- LEAVE MANAGEMENT
CREATE TABLE IF NOT EXISTS leave_types (
    id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    name            VARCHAR(100) NOT NULL, -- e.g., Annual, Sick, Unpaid
    description     VARCHAR(255) NULL,
    requires_approval TINYINT(1) NOT NULL DEFAULT 1,
    max_days_per_year DECIMAL(6,2) NULL,
    carry_forward     TINYINT(1) NOT NULL DEFAULT 0,
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_leave_types_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Types of leave policies';

CREATE TABLE IF NOT EXISTS leave_requests (
    id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id         BIGINT UNSIGNED NOT NULL,
    leave_type_id   BIGINT UNSIGNED NOT NULL,
    start_date      DATE NOT NULL,
    end_date        DATE NOT NULL,
    partial_day     ENUM('none','am','pm','hours') NOT NULL DEFAULT 'none',
    total_days      DECIMAL(6,2) NOT NULL,
    reason          VARCHAR(500) NULL,
    status          ENUM('pending','approved','rejected','cancelled') NOT NULL DEFAULT 'pending',
    approver_id     BIGINT UNSIGNED NULL,
    decision_notes  VARCHAR(500) NULL,
    requested_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    decided_at      TIMESTAMP NULL,
    PRIMARY KEY (id),
    KEY idx_leave_requests_user (user_id),
    KEY idx_leave_requests_type (leave_type_id),
    KEY idx_leave_requests_status (status),
    CONSTRAINT fk_leave_requests_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_leave_requests_type FOREIGN KEY (leave_type_id) REFERENCES leave_types(id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_leave_requests_approver FOREIGN KEY (approver_id) REFERENCES users(id) ON DELETE SET NULL ON UPDATE CASCADE,
    CHECK (start_date <= end_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Leave requests and approvals';

-- NOTIFICATIONS
CREATE TABLE IF NOT EXISTS notifications (
    id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    recipient_id    BIGINT UNSIGNED NOT NULL,
    sender_id       BIGINT UNSIGNED NULL,
    type            ENUM('system','task','meeting','attendance','leave','alert') NOT NULL,
    title           VARCHAR(200) NOT NULL,
    message         TEXT NOT NULL,
    link_url        VARCHAR(500) NULL,
    is_read         TINYINT(1) NOT NULL DEFAULT 0,
    delivered_via   SET('in_app','email','push') NOT NULL DEFAULT 'in_app',
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    read_at         DATETIME NULL,
    PRIMARY KEY (id),
    KEY idx_notifications_recipient (recipient_id, is_read),
    CONSTRAINT fk_notifications_recipient FOREIGN KEY (recipient_id) REFERENCES users(id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_notifications_sender FOREIGN KEY (sender_id) REFERENCES users(id) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Notification center entries';

-- ANALYTICS (aggregated facts and events)
CREATE TABLE IF NOT EXISTS analytics_events (
    id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id         BIGINT UNSIGNED NULL,
    event_type      VARCHAR(100) NOT NULL, -- e.g., 'productivity_alert', 'task_completed'
    event_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    context_json    JSON NULL,
    partition_day   DATE NOT NULL DEFAULT (CURRENT_DATE),
    PRIMARY KEY (id),
    KEY idx_analytics_events_user (user_id),
    KEY idx_analytics_events_type_day (event_type, partition_day),
    CONSTRAINT fk_analytics_events_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Generic analytics events with JSON context';

CREATE TABLE IF NOT EXISTS analytics_daily_user (
    id                  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id             BIGINT UNSIGNED NOT NULL,
    day                 DATE NOT NULL,
    hours_worked        DECIMAL(6,2) NULL,
    tasks_completed     INT UNSIGNED NULL,
    meetings_attended   INT UNSIGNED NULL,
    late_count          INT UNSIGNED NULL,
    early_leave_count   INT UNSIGNED NULL,
    breaks_duration_min INT UNSIGNED NULL,
    score_productivity  DECIMAL(5,2) NULL,
    score_focus         DECIMAL(5,2) NULL,
    created_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_analytics_daily_user (user_id, day),
    KEY idx_analytics_daily_user_day (day),
    CONSTRAINT fk_analytics_daily_user_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Daily analytics metrics per user';

-- INDEXES and VIEWS (optional helper indexes already included above; add example views)

-- Example view for current tasks overview
DROP VIEW IF EXISTS v_task_overview;
CREATE VIEW v_task_overview AS
SELECT
    t.id AS task_id,
    t.title,
    t.status,
    t.priority,
    p.name AS project_name,
    u1.first_name AS reporter_first_name,
    u1.last_name AS reporter_last_name,
    u2.first_name AS assignee_first_name,
    u2.last_name AS assignee_last_name,
    t.due_date
FROM tasks t
LEFT JOIN projects p ON p.id = t.project_id
JOIN users u1 ON u1.id = t.reporter_id
LEFT JOIN users u2 ON u2.id = t.assignee_id;

-- Example view for attendance summary by day
DROP VIEW IF EXISTS v_attendance_summary;
CREATE VIEW v_attendance_summary AS
SELECT
    a.user_id,
    a.attendance_date,
    a.check_in_time,
    a.check_out_time,
    a.total_work_seconds,
    a.is_late,
    a.is_early_leave,
    a.source
FROM attendance a;

-- Restore safety toggles
SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS;
SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS;
