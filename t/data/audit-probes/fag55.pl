my @a=(1,2); my $o={k=>\@a}; my @c=@{$o->{k}}; shift @a; print scalar(@c),"\n";
