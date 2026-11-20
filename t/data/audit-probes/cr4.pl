my $o = {}; for my $c ("A", "B") { print ref($o), " "; bless $o, $c } print ref($o), "\n";
