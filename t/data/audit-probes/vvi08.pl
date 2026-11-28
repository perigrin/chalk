my $s = "abc"; my $u = "x"; $s =~ s/b/$u/; $u = "y"; $s =~ s/c/$u/; print "$s\n";
