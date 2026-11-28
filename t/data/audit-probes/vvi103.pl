my $s = "aabb"; (my $t = $s) =~ s/(a+)(b+)/$2$1/; print "$t$1$2\n";
