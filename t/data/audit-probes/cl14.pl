my $x = "a\n"; my $g = sub { $x }; chomp $x; print "[", $g->(), "]\n";
