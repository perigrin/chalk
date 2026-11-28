our %h = (a=>1); my $c = sub { join(",", sort keys %h) }; { local %h = (b=>2); print $c->() } print $c->(), "\n";
