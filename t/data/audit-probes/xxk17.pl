my $s = "abc"; my $u = ""; $s =~ s/(.)/$u .= $1; uc $1/ge; print "$s$u\n";
