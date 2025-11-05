# ABOUTME: Source location tracking for IR nodes with file, line, column, and byte position
# ABOUTME: Enables detailed error messages showing exact source location with context
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;

class Chalk::IR::SourceInfo {
    field $file_path  :param :reader;
    field $start_line :param :reader;
    field $start_col  :param :reader;
    field $end_line   :param :reader;
    field $end_col    :param :reader;
    field $start_pos  :param :reader;
    field $end_pos    :param :reader;

    # Calculate the length of the source span in bytes
    method span_length() {
        return $end_pos - $start_pos;
    }

    # Format source location as string for error messages
    method to_string() {
        if ($start_line == $end_line) {
            # Single line span
            return sprintf("%s:%d:%d-%d",
                $file_path, $start_line, $start_col, $end_col);
        } else {
            # Multi-line span
            return sprintf("%s:%d:%d-%d:%d",
                $file_path, $start_line, $start_col, $end_line, $end_col);
        }
    }
}

1;
