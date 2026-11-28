my $s = "a"; sub w { $s = "b" . $s; $s = "$s$s"; $s } print w(), "\n";
