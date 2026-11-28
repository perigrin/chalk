sub w { my ($s) = @_; $s = "<" . $s; $s = "$s$s"; $s } print w("a"), "\n";
