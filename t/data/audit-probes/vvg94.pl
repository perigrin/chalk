sub mk { my @a = @_; sub { shift @a } } my $it = mk(1,2,3); $it->(); print $it->(), "\n";
