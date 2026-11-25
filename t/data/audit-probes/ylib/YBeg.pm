# ABOUTME: Library code for the y/yd probes (third final audit, 2026-11-25):
# ABOUTME: a followed module with its own BEGIN block and file-level code after it.
package YBeg;
our $n; BEGIN { $n = 5 } $n++; sub get { $n }
1;
