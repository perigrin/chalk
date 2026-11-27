my %h = (a=>1,b=>2,c=>3); my @k; while (my $k = each %h) { push @k, $k } print join(",", sort @k), "\n";
