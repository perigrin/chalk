my $s = "abc"; my $u = "b"; $s =~ s/$u/z/; $u = "c"; $s =~ s/$u/w/; print "$s\n";
