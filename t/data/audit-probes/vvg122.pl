{ my $priv = 10; sub getp { $priv } sub setp { $priv = shift } } setp(5); print getp(), "\n";
