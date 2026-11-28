my $s = "abc"; my $t = $s =~ /b/ ? "y" : "n"; my $u = $s !~ /b/ ? "y" : "n"; my ($v) = $s =~ /(z)/; print "$t$u", defined $v ? "d" : "u", "\n";
