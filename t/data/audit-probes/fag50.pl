my @a=(1,2); my $o={k=>\@a}; my @c=@a; push @{$o->{k}},3; print scalar(@c),"\n";
