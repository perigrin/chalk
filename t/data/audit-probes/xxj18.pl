my $s = "a1b2"; my $t = 0; $s =~ s/(\d)/$t += $1; $t/ge; print "$s$t\n";
