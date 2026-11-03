// Applies <app>-api/db/migrations/*.sql, in file-name order, to the app's own schema in the shared
// database: each ${schema} in a file is replaced with the schema name, and each file runs in its own
// transaction. Every file is applied on every run, so migrations must be idempotent (IF NOT EXISTS).
// Reads the connection from <app>-api/.env (values are never printed). With --dry-run, every file
// is applied and then rolled back. Run via apply-migrations.cmd.
//   java --class-path <postgresql.jar> ApplyMigrations.java <api dir> <schema> [--dry-run]
import java.nio.file.*;
import java.sql.*;
import java.util.*;
import java.util.stream.Stream;

public class ApplyMigrations {
    public static void main(String[] args) throws Exception {
        Path apiDir = Path.of(args[0]);
        String schema = args[1];
        boolean dryRun = args.length > 2 && args[2].equals("--dry-run");
        // The name is substituted into SQL, so allow only a plain lower-case PostgreSQL identifier.
        if (!schema.matches("[a-z_][a-z0-9_]{0,62}")) throw new IllegalArgumentException("Invalid schema name: " + schema);

        Map<String, String> env = new HashMap<>();
        for (String line : Files.readAllLines(apiDir.resolve(".env"))) {
            if (line.startsWith("#") || !line.contains("=")) continue;
            int i = line.indexOf('=');
            env.put(line.substring(0, i).trim(), line.substring(i + 1).trim().replace("\\\\", "\\"));
        }
        List<Path> files;
        try (Stream<Path> listing = Files.list(apiDir.resolve("db/migrations"))) {
            files = listing.filter(f -> f.toString().endsWith(".sql")).sorted().toList();
        }

        try (Connection c = DriverManager.getConnection(env.get("DATABASE_URL"), env.get("DATABASE_USERNAME"), env.get("DATABASE_PASSWORD"))) {
            c.setAutoCommit(false);
            for (Path file : files) {
                String sql = Files.readString(file).replace("${schema}", schema);
                try (Statement s = c.createStatement()) {
                    s.execute(sql);
                    if (dryRun) c.rollback(); else c.commit();
                    System.out.println((dryRun ? "checked (rolled back) " : "applied ") + file.getFileName() + " to schema " + schema);
                } catch (SQLException e) {
                    c.rollback();
                    throw e;
                }
            }
        }
    }
}
