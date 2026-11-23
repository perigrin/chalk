my @stack; sub psh { push @stack,@_ } sub pp { pop @stack } psh(1,2); my $t=pp(); psh(3); print $t, "@stack\n";
