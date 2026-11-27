my $s = "a-b"; $s =~ s/(\w)/ $1 eq "a" ? "A" : do { my $t = $1; $t x 2 } /ge; print "$s\n";
