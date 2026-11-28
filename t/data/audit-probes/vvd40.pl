my %h = (a=>1,b=>2); my ($k, %r) = ("x", %h); print "$k", join(",", sort keys %r), "\n";
