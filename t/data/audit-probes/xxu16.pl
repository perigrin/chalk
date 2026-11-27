our $x = 1; sub c { $x = 3; "c" } my $s = index("abcabc", c(), $x) . index("abcabc", "a", $x); print "$s\n";
