my @a=(1,2); $_++ for @{[ @a ]}; $_++ for (my @c = @a); sub f { @a } $_++ for f(); $_ = uc for (my @w = qw(a b)); print "@a@c@w\n";
