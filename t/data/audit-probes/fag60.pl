sub f { my $l=shift; my @c=@$l; push @$l,9; return scalar @c } print f([1,2]),"\n";
