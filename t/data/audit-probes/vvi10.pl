my $s = "a.b"; my $u = "."; $s =~ s/\Q$u\E/-/; print "$s\n";
