sub ap { push @{$_[0]}, $_[1] } my $l=[]; ap($l,1); my @c=@$l; ap($l,3); print scalar(@c), "\n";
