my $s = "a"; $s = "b" . $s; $s = join("", $s, $s); print "$s\n";
