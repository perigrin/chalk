my @r; for my $i (1..3) { push @r, \$i } my @s; for my $i (1..3) { push @s, \$i } print $r[0] == $s[0] ? "s" : "d", $r[0] == $r[1] ? "s" : "d", "\n";
