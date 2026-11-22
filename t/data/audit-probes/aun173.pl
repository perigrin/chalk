my $s = "abc"; my $r = \$s; my $u = uc $s; $$r =~ s/a/x/; print "$u $s\n";
