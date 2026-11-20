sub n { my %l = @_; return %l ? scalar(%l) : -1 } print n(a => 1, b => 2), " ", n(), "\n";
