my $s = ""; my ($x, @a) = (1, 2, 3); eval { for my $e ($x, @a, 4) { $e++ } }; print "$x@a", $@ ? "ro" : "ok", "\n";
