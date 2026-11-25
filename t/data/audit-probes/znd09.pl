my %g=(a=>["b","c"],b=>["c"],c=>[]); my %seen; my @st=("a"); my @o; while (@st) { my $n=pop @st; next if $seen{$n}++; push @o,$n; push @st, reverse @{$g{$n}} } print "@o\n";
