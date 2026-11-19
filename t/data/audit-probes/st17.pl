my $o = {}; my @r; for my $c ("A", "B") { push @r, ref($o); bless $o, $c } print "@r ", ref($o), "\n";
