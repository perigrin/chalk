my $x = 1; my $g = sub { $x }; if (@ARGV) { $x = 2 } else { $x = 3 } print $g->(), "\n";
