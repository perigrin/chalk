my $x; eval { $x->method }; print $@ =~ /undefined value/ ? "undef" : "no", "\n";
