my $o = {}; my @a = (1); if (!@a) { bless $o, "X" } print ref($o), "\n"; if (@a) { bless $o, "Y" } print ref($o), "\n";
