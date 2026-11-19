my @o = ({}, {}); my @r; for my $i (0, 1) { push @r, ref($o[$i]); bless $o[$i], "K$i"; push @r, ref($o[$i]) } print "@r\n";
