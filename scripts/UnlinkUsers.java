// One-off maintenance: unlinks every admin.users row from its old Cognito identity (cognito_sub = NULL)
// so project-0's new user pool can link rows again by verified email on next sign-in.
// Names, phone numbers and emails are kept. Reads the connection from project-0-api\.env (values
// are never printed), writes a CSV backup of the table to logs\ first, and runs in one transaction.
// Run via unlink-users.cmd.
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.sql.*;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;

public class UnlinkUsers {
    public static void main(String[] args) throws Exception {
        Path root = Path.of(args.length > 0 ? args[0] : ".");
        Map<String, String> env = new HashMap<>();
        for (String line : Files.readAllLines(root.resolve("project-0-api/.env"))) {
            if (line.startsWith("#") || !line.contains("=")) continue;
            int i = line.indexOf('=');
            env.put(line.substring(0, i).trim(), line.substring(i + 1).trim().replace("\\\\", "\\"));
        }
        String stamp = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss"));
        Path backup = root.resolve("logs/admin-users-backup-" + stamp + ".csv");
        try (Connection c = DriverManager.getConnection(env.get("DATABASE_URL"), env.get("DATABASE_USERNAME"), env.get("DATABASE_PASSWORD"))) {
            c.setAutoCommit(false);
            int total = 0, linked = 0;
            StringBuilder csv = new StringBuilder("id,email,first_name,last_name,phone_number,cognito_sub,create_date,update_date,create_user,update_user\n");
            try (Statement s = c.createStatement(); ResultSet r = s.executeQuery(
                    "SELECT id,email,first_name,last_name,phone_number,cognito_sub,create_date,update_date,create_user,update_user FROM admin.users ORDER BY id FOR UPDATE")) {
                int cols = r.getMetaData().getColumnCount();
                while (r.next()) {
                    total++;
                    if (r.getString("cognito_sub") != null) linked++;
                    List<String> cells = new ArrayList<>();
                    for (int k = 1; k <= cols; k++) {
                        String v = r.getString(k);
                        cells.add(v == null ? "" : "\"" + v.replace("\"", "\"\"") + "\"");
                    }
                    csv.append(String.join(",", cells)).append('\n');
                }
            }
            Files.writeString(backup, csv.toString(), StandardCharsets.UTF_8);
            System.out.println("backup: " + backup + " (" + total + " rows, " + linked + " linked to a Cognito identity)");
            int changed;
            try (Statement s = c.createStatement()) {
                changed = s.executeUpdate("UPDATE admin.users SET cognito_sub = NULL WHERE cognito_sub IS NOT NULL");
            }
            c.commit();
            System.out.println("unlinked: " + changed + " rows (cognito_sub cleared; all other columns unchanged)");
            System.out.println("DONE");
        }
    }
}
