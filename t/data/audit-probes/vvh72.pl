my $c; eval { $c->() }; print $@ =~ /Can't use an undefined value as a subroutine/ ? "undefcode" : "no", "\n";
