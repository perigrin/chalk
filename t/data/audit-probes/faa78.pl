sub ap { push @{$_[0]}, $_[1]; $_[0] } my $l=[]; ap(ap($l,1),2); my @c=@$l; ap($l,3); print scalar(@c), scalar(@$l), "\n";
