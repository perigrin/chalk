my $z=@ARGV; eval { my $x=sqrt($z-1) }; print $@ ? "died":"ok","\n";
