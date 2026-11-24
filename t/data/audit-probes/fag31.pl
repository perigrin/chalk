my $l=[1,2]; sub ap { push @{$_[0]},3 } my @c=@$l; ap($l); print scalar(@c),"\n";
