sub w { my $s = shift; $s = "b" . $s; $s = "$s$s"; $s } print w("a"), "\n";
