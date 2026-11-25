use Cwd qw(getcwd); print getcwd() =~ m{^/} ? "abs" : "rel", "\n";
