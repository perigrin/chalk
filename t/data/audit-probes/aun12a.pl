my $h = { l => [1] }; my $l = $h->{l}; my $n = @$l; push @{ $h->{l} }, 2; print "$n ", scalar(@$l), "\n";
