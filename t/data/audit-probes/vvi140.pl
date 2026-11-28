my $s = "abc"; my $t = join "", reverse split //, $s; my $u = scalar reverse $s; print "$t$u\n";
