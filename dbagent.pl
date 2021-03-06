#!/usr/local/bin/perl

#------------
#--- AUTH ---
#------------

package aAuth;

use strict;
use warnings;
use POSIX qw(getpid setuid setgid geteuid getegid);
use Cwd qw(cwd getcwd chdir);
use Mojo::Util qw(md5_sum b64_decode dumper);
use Apache::Htpasswd;

sub new {
    my ($class, $pwdfile) = @_;
    my $self = {
        pwdfile => $pwdfile,
        errstr => undef
    };
    bless $self, $class;
    return $self;
}

sub pwdfile {
    my ($self, $pwdfile) = @_;
    return $self->{pwdfile} unless $pwdfile;
    $self->{pwdfile} = $pwdfile if $pwdfile;
    $self;
}

sub auth {
    my ($self, $authstr) = @_;
    return undef unless $authstr;

    my $hash = $self->split($authstr);
    return undef unless $hash;
    return undef unless -r $self->{pwdfile};

    my $res = undef;
    eval {
        my $ht = Apache::Htpasswd->new( { passwdFile => $self->pwdfile, ReadOnly => 1 } );
        $res = $ht->htCheckPassword(
                            $hash->{username},
                            $hash->{password}
        );
    };
    return undef if $@;
    $res;
}

sub username {
    my ($self, $authstr) = @_;
    return undef unless $authstr;
    my $hash = $self->split($authstr);
    return undef unless $hash;
    $hash->{username} if $hash;
}

sub split {
    my ($self, $authstr) = @_;
    return undef unless $authstr;

    my ($type, $enc) = split /\s+/, $authstr;
    return undef unless ($type eq 'Basic' && $enc);

    my ($username, $password) = split /:/, b64_decode($enc);
    return undef unless ($username && $password);

    { username => $username, password => $password };
}

1;


#--------------
#--- CONFIG ---
#--------------

package aConfig;

use strict;
use warnings;

sub new {
    my ($class, $file) = @_;
    my $self = {
        file => $file
    };
    bless $self, $class;
    $self;
}

sub file {
    my ($self, $name) = @_;
    return $self->{'file'} unless $name;
    $self->{'file'} = $name;
    $self;
}

sub read {
    my $self = shift;
    return undef unless -r $self->file;
    open my $fh, '<', $self->file;
    my %res;
    while (my $line = readline $fh) {
        chomp $line;
        $line =~ s/^\s+//g;

        next if $line =~ /^#/;
        next if $line =~ /^;/;
        next unless $line =~ /[=:]/;

        $line =~ s/[\"\']//g;
        my ($key, $rawvalue) = split(/==|=>|=/, $line);
        next unless $rawvalue and $key;

        my ($value, $comment) = split(/[#;,]/, $rawvalue);

        $key =~ s/^\s+|\s+$//g;
        $value =~ s/^\s+|\s+$//g;

        $res{$key} = $value;
    }
    close $fh;
    \%res;
}

1;

#--------------
#--- DAEMON ---
#--------------

package aDaemon;

use strict;
use warnings;
use POSIX qw(getpid setuid setgid geteuid getegid);
use Cwd qw(cwd getcwd chdir);
use Mojo::Util qw(dumper);

sub new {
    my ($class, $user, $group)  = @_;
    my $self = {
        user => $user,
        group => $group
    };
    bless $self, $class;
    return $self;
}

sub fork {
    my $self = shift;

    my $pid = fork;
    if ($pid > 0) {
        exit;
    }
    chdir("/");

    my $uid = getpwnam($self->{user}) if $self->{user};
    my $gid = getgrnam($self->{group}) if $self->{group};

    setuid($uid) if $uid;
    setgid($gid) if $gid;

    open(my $stdout, '>&', STDOUT); 
    open(my $stderr, '>&', STDERR);
    open(STDOUT, '>>', '/dev/null');
    open(STDERR, '>>', '/dev/null');
    getpid;
}

1;

#--------------
#--- STOREI ---
#--------------

package aStoreI;

use strict;
use warnings;
use Mojo::UserAgent;
use Mojo::JSON qw(encode_json decode_json);
use Mojo::Util qw(dumper);

sub new {
    my ($class, $host, $login, $password) = @_;
    my $ua = Mojo::UserAgent->new;

    $ua->max_response_size(10*1024*1024*1024);
    $ua->inactivity_timeout(60);
    $ua->connect_timeout(60);
    $ua->request_timeout(2*60*60);

    my $self = {
        host => $host,
        login => $login,
        password => $password,
        port => '8184',
        ua => $ua
    };
    bless $self, $class;
    return $self;
}

sub ua {
    my ($self, $ua) = @_;
    return $self->{ua} unless $ua;
    $self->{ua} = $ua;
    $self;
}

sub host {
    my ($self, $host) = @_;
    return $self->{host} unless $host;
    $self->{host} = $host;
    $self;
}

sub login {
    my ($self, $login) = @_;
    return $self->{login} unless $login;
    $self->{login} = $login;
    $self;
}

sub password {
    my ($self, $password) = @_;
    return $self->{password} unless $password;
    $self->{password} = $password;
    $self;
}

sub port {
    my ($self, $port) = @_;
    return $self->{port} unless $port;
    $self->{port} = $port;
    $self;
}


sub rpc {
    my ($self,  $call, %args) = @_;
    return undef unless $call;
    return undef unless $call =~ /^\//;

    my $host = $self->host;
    my $login = $self->login;
    my $password = $self->password;
    my $port = $self->port;

    my $url = "https://$login:$password\@$host:$port$call";
    $url .= "?" if %args;
    foreach my $key (sort keys %args) {
        my $value = $args{$key};
        next unless $value;
        $url .= "&$key=$value";
    }

    $url =~ s/\?&/\?/;
    my $res;
    eval {
        my $tx = $self->ua->get($url);
        $res = $tx->result->body;
    };
    return undef if $@;
    my $j = decode_json($res);
}


sub alive {
    my $self = shift;
    my $res = $self->rpc('/hello');
    return 1 if  $res->{'message'} eq 'hello';
    return undef;
}

sub data_list {
    my $self = shift;
    $self->rpc('/data/list');
}

sub data_profile {
    my ($self, $name) = @_;
    $self->rpc('/data/profile', name => $name);
}

sub data_delete {
    my ($self, $name) = @_;
    $self->rpc('/data/delete', name => $name);
}

sub store_profile {
    my ($self) = @_;
    $self->rpc('/store/profile');
}


sub data_get {
    my ($self, $name, $dir) = @_;

    return undef unless $dir;
    return undef unless -w $dir;

    my $host = $self->host;
    my $login = $self->login;
    my $password = $self->password;
    my $port = $self->port;

    $ENV{MOJO_TMPDIR} = $dir;

    my $tx = $self->ua->get("https://$login:$password\@$host:$port/data/get?name=$name");
    my $res = $tx->result;

    my $type = $res->headers->content_type || '';
    my $disp = $res->headers->content_disposition || '';
    my $file = "$dir/$name";

    if ($type =~ /name=/ or $disp =~ /filename=/) {
        my ($filename) = $disp =~ /filename=\"(.*)\"/;
        rename $file, "$file.bak" if -r $file;
        $res->content->asset->move_to($file);
    }
    return undef unless -r $file;
    $file;
}

sub data_put {
    my ($self, $file) = @_;

    return undef unless $file;
    return undef unless -r $file;

    my $host = $self->host;
    my $login = $self->login;
    my $password = $self->password;
    my $port = $self->port;

    my $url = "https://$login:$password\@$host:$port/data/put";
    my $res;
    eval {
        my $tx = $self->ua->post($url => form => {data => { file => $file } });
        $res = $tx->result->body;
    };
    return undef if $@;
    my $j = decode_json($res);
}

sub dump_clean {
    my ($self, $pattern, $remain) = @_;
    $self->rpc('/dump/clean', pattern => $pattern, remain => $remain);
}


1;

#-----------
#--- DBI ---
#-----------

package aDBI;

use strict;
use warnings;
use DBI;
use DBD::Pg;

sub new {
    my ($class, %args) = @_;
    my $self = {
        host => $args{host} || '127.0.0.1',
        login => $args{login} || 'postgres',
        password => $args{password} || 'password',
        database => $args{database} || 'postgres',
        engine => $args{engine} || 'Pg',
        error => ''
    };
    bless $self, $class;
    return $self;
}

sub login {
    my ($self, $login) = @_;
    return $self->{login} unless $login;
    $self->{login} = $login;
    $self;
}

sub password {
    my ($self, $password) = @_;
    return $self->{password} unless $password;
    $self->{password} = $password;
    $self;
}

sub host {
    my ($self, $host) = @_;
    return $self->{host} unless $host;
    $self->{host} = $host;
    $self;
}

sub database {
    my ($self, $database) = @_;
    return $self->{database} unless $database;
    $self->{database} = $database;
    $self;
}

sub error {
    my ($self, $error) = @_;
    return $self->{error} unless $error;
    $self->{error} = $error;
    $self;
}

sub engine {
    my ($self, $engine) = @_;
    return $self->{engine} unless $engine;
    $self->{engine} = $engine;
    $self;
}

sub exec {
    my ($self, $query) = @_;
    return undef unless $query;

    my $dsn = 'dbi:'.$self->engine.
                ':dbname='.$self->database.
                ';host='.$self->host;
    my $dbi;
#    eval {
        $dbi = DBI->connect($dsn, $self->login, $self->password, {
            RaiseError => 1,
            PrintError => 0,
            AutoCommit => 1
        });
#    };
    $self->error($@);
    return undef if $@;

    my $sth;
#    eval {
        $sth = $dbi->prepare($query);
#    };
    $self->error($@);
    return undef if $@;

    my $rows = $sth->execute;
    my @list;

    while (my $row = $sth->fetchrow_hashref) {
        push @list, $row;
    }
    $sth->finish;
    $dbi->disconnect;
    \@list;
}

sub exec1 {
    my ($self, $query) = @_;
    return undef unless $query;

    my $dsn = 'dbi:'.$self->engine.
                ':dbname='.$self->database.
                ';host='.$self->host;
    my $dbi;
#    eval {
        $dbi = DBI->connect($dsn, $self->login, $self->password, {
            RaiseError => 1,
            PrintError => 0,
            AutoCommit => 1
        });
#    };
    $self->error($@);
    return undef if $@;

    my $sth;
#    eval {
        $sth = $dbi->prepare($query);
#    };
    $self->error($@);
    return undef if $@;

    my $rows = $sth->execute;
    my $row = $sth->fetchrow_hashref;

    $sth->finish;
    $dbi->disconnect;
    $row;
}

sub do {
    my ($self, $query) = @_;
    return undef unless $query;
    my $dsn = 'dbi:'.$self->engine.
                ':dbname='.$self->database.
                ';host='.$self->host;
    my $dbi;
#    eval {
        $dbi = DBI->connect($dsn, $self->login, $self->password, {
            RaiseError => 1,
            PrintError => 0,
            AutoCommit => 1
        });
#    };
    $self->error($@);
    return undef if $@;
    my $rows;
#    eval {
        $rows = $dbi->do($query);
#    };
    $self->error($@);
    return undef if $@;

    $dbi->disconnect;
    $rows*1;
}

1;

#-------------
#--- AGENT ---
#-------------

package aAgent;

use strict;
use warnings;
use File::stat;
use Data::Dumper;
use DBI;
use Mojo::UserAgent;
use Mojo::Util qw(dumper url_escape);
use Mojo::JSON qw(encode_json decode_json true false);
use POSIX;
use Socket;

sub new {
    my ($class, $dbi) = @_;
    my $self = {
        dbi => $dbi
    };
    bless $self, $class;
    return $self;
}

sub dbi { 
    my ($self, $dbi) = @_;
    return $self->{dbi} unless $dbi;
    $self->{dbi} = $dbi;
    $self;
}

# --- DATABASES ---

sub db_exist {
    my ($self, $name) = @_;
    return undef unless $name;
    my $dblist = $self->db_list;
    foreach my $db (@$dblist) {
        return 1 if $db->{"name"} eq $name;
    }
    return undef;
}

sub db_size {
    my ($self, $name) = @_;
    return undef unless $name;
    return undef unless $self->db_exist($name);
    my $query = "select '$name' as name, pg_database_size('$name') as size;";
    $self->dbi->exec1($query)->{size};
}

sub db_list {
    my $self = shift;
    my $query = "select d.datname as name,
                        pg_database_size(d.datname) as size,
                        u.usename as owner,
                        s.numbackends as numbackends
                    from pg_database d, pg_user u, pg_stat_database s
                    where d.datdba = u.usesysid and d.datname = s.datname
                    order by d.datname;";
    $self->dbi->exec($query);
}

sub db_profile {
    my ($self, $name) = @_;
    return undef unless $name;

    my $query = "select d.datname as name,
                        pg_database_size(d.datname) as size,
                        u.usename as owner,
                        s.numbackends as numbackends
                    from pg_database d, pg_user u, pg_stat_database s
                    where d.datdba = u.usesysid and d.datname = s.datname
                        and d.datname = '$name' limit 1";
    $self->dbi->exec1($query);
}

sub db_create {
    my ($self, $name) = @_;
    return undef unless $name;
    return undef if $self->db_exist($name);
    my $query = "create database $name";
    $self->dbi->do($query);
    $self->db_exist($name);
}

sub db_drop {
    my ($self, $name) = @_;
    return undef unless $name;
    return undef unless $self->db_exist($name);
    my $query = "drop database $name";
    $self->dbi->do($query);
    return undef if $self->db_exist($name);
    1;
}

sub db_copy {
    my ($self, $name, $new_name) = @_;
    return undef unless $name;
    return undef unless $new_name;
    return undef unless $self->db_exist($name);
    return undef if $self->db_exist($new_name);

    my $query = "create database $new_name template $name";
    $self->dbi->do($query);
    $self->db_exist($new_name);
}


sub db_rename {
    my ($self, $name, $new_name) = @_;
    return undef unless $name;
    return undef unless $new_name;
    return undef unless $self->db_exist($name);

    my $query = "alter database $name rename to $new_name";
    $self->dbi->do($query);
    $self->db_exist($new_name);
}

sub db_owner {
    my ($self, $name, $user) = @_;
    return undef unless $name;
    return undef unless $self->db_exist($name);
#    my $query = "select u.usename as username, d.datname as db_name
#                        from pg_database d, pg_user u
#                        where d.datdba = u.usesysid and d.datname = '$name' limit 1";
    return undef unless $self->user_exist($user);

    my $query = "alter database $name owner to $user";
    $self->dbi->do($query);
    $self->db_exist($name);
}

#-------------------
#--- AGENT USER ----
#-------------------

sub user_list {
    my $self = shift;
    my $query = "select usename as name from pg_user order by usename";
    $self->dbi->exec($query);
}

sub user_profile {
    my ($self, $name) = @_;
    return undef unless $name;
    my $query = "select usename as name from pg_user where usename = '$name' limit 1";
    $self->dbi->exec1($query);
}

sub user_exist {
    my ($self, $name) = @_;
    return undef unless $name;
    return 1 if $self->user_profile($name);
    undef;
}

sub user_create {
    my ($self, $name, $password) = @_;
    return undef unless $name;
    return undef unless $password;
    return undef if $self->user_profile($name);

    my $query = "create user $name encrypted password '$password'";
    $self->dbi->do($query);
    $self->user_exist($name);
}

sub user_drop {
    my ($self, $name) = @_;
    return undef unless $name;
    return undef unless $self->user_exist($name);

    my $query = "drop user $name";
    $self->dbi->do($query);
    return undef if $self->user_exist($name);
    $name;
}

sub user_password {
    my ($self, $name, $password) = @_;
    return undef unless $password;
    return undef unless $name;
    return undef unless $self->user_exist($name);

    my $query = "alter user $name encrypted password '$password'";
    $self->dbi->do($query);
    $self->user_exist($name);
}

sub user_rename {
    my ($self, $name, $new_name) = @_;
    return undef unless $new_name;
    return undef unless $name;
    return undef if $self->user_exist($name);

    my $query = "alter user $name rename to $new_name";
    $self->dbi->do($query);
    $self->user_exist($new_name);
}

sub db_dump {
    my ($self, $name, $dir) = @_;

    return undef unless $name;
    return undef unless $self->db_exist($name);

    return undef unless -d $dir;
    return undef unless -w $dir;

    my $host = $self->dbi->host;
    my $login = $self->dbi->login;
    my $password = $self->dbi->password;

    my $timestamp = strftime("%Y%m%d-%H%M%S-%Z", localtime(time));
    my $file = "$dir/$name--$timestamp--$host.sqlz";

    my $out = qx/PGPASSWORD=$password pg_dump -h $host -U $login -Fc -f $file $name 2>&1/;
    my $retcode = $?;

    return $file if $retcode == 0;
    undef;
}

sub db_restore {
    my ($self, $file, $name) = @_;
    return undef unless $name;
    return undef unless $file;
    return undef unless -r $file;
#    return undef unless -s $file;

    return undef if $self->db_exist($name);
    return undef unless $self->db_create($name);

    my $host = $self->dbi->host;
    my $password = $self->dbi->password;
    my $login = $self->dbi->login;

    my $out = qx/PGPASSWORD=$password pg_restore -j4 -h $host -U $login -Fc -d $name $file 2>&1 /;
    my $retcode = $?;

#    if ($retcode > 1) {
#        $self->db_drop($name) if $self->db_exist($name);
#        return undef;
#    }
    $name;
}


1;


#--------------------
#--- CONTROLLER 1 ---
#--------------------

package DBagent::Controller;

use utf8;
use strict;
use warnings;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Util qw(md5_sum dumper quote encode url_unescape);
use Mojo::JSON qw(encode_json decode_json false true);
use File::Basename;
use Filesys::Df;
use File::stat;
use POSIX;

sub datadir {
    my ($self, $dir) = @_;
    return $self->app->config('datadir') unless $dir;
    $self->app->config(datadir => $dir);
    $self;
}

sub hello {
    my $self = shift;
    $self->render(json => { message => 'hello', success => 1 });
}

sub db_list {
    my $self = shift;
    my $list = $self->app->agent->db_list;
    return $self->render(json => { success => 0 }) unless $list;
    $self->render(json => { list => $list, success => 1 });
}


sub db_profile {
    my $self = shift;

    my $name = $self->req->param('name');
    return $self->render(json => { success => 0 }) unless $name;

    my $list = $self->app->agent->db_profile($name);

    return $self->render(json => { success => 0 }) unless $list;
    $self->render(json => { profile => $list, success => 1 });
}


sub db_create {
    my $self = shift;
    my $name = $self->req->param('name');
    return $self->render(json => { success => 0 }) unless $name;

    my $res = $self->app->agent->db_create($name);

    return $self->render(json => { success => 0 }) unless $res;
    $self->render(json => { success => 1 });
}

sub db_copy {
    my $self = shift;
    my $name = $self->req->param('name');
    my $new_name = $self->req->param('new_name');
    return $self->render(json => { success => 0 }) unless $name;
    return $self->render(json => { success => 0 }) unless $new_name;

    my $res = $self->app->agent->db_copy($name, $new_name);

    return $self->render(json => { success => 0 }) unless $res;
    $self->render(json => { success => 1 });
}


sub db_drop {
    my $self = shift;
    my $name = $self->req->param('name');
    return $self->render(json => { success => 0 }) unless $name;

    my $res = $self->app->agent->db_drop($name);

    return $self->render(json => { success => 0 }) unless $res;
    $self->render(json => { success => 1 });

}

sub db_rename {
    my $self = shift;

    my $name = $self->req->param('name');
    my $new_name = $self->req->param('new_name');

    return $self->render(json => { success => 0 }) unless $name;
    return $self->render(json => { success => 0 }) unless $new_name;

    my $res = $self->app->agent->db_rename($name, $new_name);

    return $self->render(json => { success => 0 }) unless $res;
    $self->render(json => { success => 1 });
}

sub db_owner {
    my $self = shift;
    my $name = $self->req->param('name');
    my $owner = $self->req->param('owner');

    return $self->render(json => { success => 0 }) unless $name;
    return $self->render(json => { success => 0 }) unless $owner;

    my $res = $self->app->agent->db_owner($name, $owner);

    return $self->render(json => { success => 0 }) unless $res;
    $self->render(json => { success => 1 });
}


sub user_list {
    my $self = shift;
    my $list = $self->app->agent->user_list;
    return $self->render(json => { success => 0 }) unless $list;
    $self->render(json => { list => $list, success => 1 });
}

sub user_profile {
    my $self = shift;
    my $name = $self->req->param('name');
    return $self->render(json => { success => 0 }) unless $name;

    my $res = $self->app->agent->user_profile($name);

    return $self->render(json => { success => 0 }) unless $res;
    $self->render(json => { profile => $res, success => 1 });
}

sub user_create {
    my $self = shift;

    my $name = $self->req->param('name');
    my $password = $self->req->param('password');

    return $self->render(json => { success => 0 }) unless $name;
    return $self->render(json => { success => 0 }) unless $password;

    my $res = $self->app->agent->user_create($name, $password);

    return $self->render(json => { success => 0 }) unless $res;
    $self->render(json => { success => 1 });
}

sub user_drop {
    my $self = shift;
    my $name = $self->req->param('name');
    return $self->render(json => { success => 0 }) unless $name;

    my $res = $self->app->agent->user_drop($name);

    return $self->render(json => { success => 0 }) unless $res;
    $self->render(json => { success => 1 });
}

sub user_rename {
    my $self = shift;

    my $name = $self->req->param('name');
    my $new_name = $self->req->param('new_name');

    return $self->render(json => { success => 0 }) unless $name;
    return $self->render(json => { success => 0 }) unless $new_name;

    my $res = $self->app->agent->user_rename($name, $new_name);

    return $self->render(json => { success => 0 }) unless $res;
    $self->render(json => { success => 1 });

}

sub user_password {
    my $self = shift;

    my $name = $self->req->param('name');
    my $password = $self->req->param('password');

    return $self->render(json => { success => 0 }) unless $name;
    return $self->render(json => { success => 0 }) unless $password;

    my $res = $self->app->agent->user_rename($name, $password);

    return $self->render(json => { success => 0 }) unless $res;
    $self->render(json => { success => 1 });

}


sub db_dump {
    my $self = shift;

    my $name = $self->req->param('name');
    my $store = $self->req->param('store');
    my $login = $self->req->param('login');
    my $password = $self->req->param('password');
    my $cb = $self->req->param('cb');
    my $job_id = $self->req->param('job_id');
    my $magic = $self->req->param('magic');

    return $self->render(json => { success => 0 }) unless $name;

    return $self->render(json => { success => 0 }) unless $store;
    return $self->render(json => { success => 0 }) unless $login;
    return $self->render(json => { success => 0 }) unless $password;

    return $self->render(json => { success => 0 }) unless $cb;
    return $self->render(json => { success => 0 }) unless $job_id;
    return $self->render(json => { success => 0 }) unless $magic;


    my $sub = Mojo::IOLoop::Subprocess->new;

    $sub->run(
        sub {
            my $sub = shift;
            my $app = $self->app;
            my $dir = $app->app->config('datadir');

            $app->log->info("--- The dump begins name=$name job=$job_id");
            my $file = $app->agent->db_dump($name, $dir);

            unless ($file) {
                $app->log->info("--- The dump unsuccessful name=$name job_id=$job_id");
                return undef;
            }
            $app->log->info("--- The dump is done name=$name job_id=$job_id file=$file");

            # ---Upload the dump ---
            $app->log->info("--- The upload begins file=$file job_id=$job_id store=$store");

            my $store = aStoreI->new($store, $login, $password);
            unless ($store->alive) {
                unlink $file;
                $app->log->info("--- The upload unsuccessful because store is dead store=$store job_id=$job_id");
                return undef;
            }
            my $res = $store->data_put($file);

            my $size = stat($file)->size;
            my $res_size = $res->{list}->[0]->{size} || 0;
            my $res_file = $res->{list}->[0]->{size} || '';

            $app->log->info("--- The upload size is $res_size res_file=$res_file job_id=$job_id");

            unless ($res_size == $size) {
                $app->log->info("--- The upload unsuccessful name=$name job_id=$job_id file=$file");
                unlink $file;
                $store->data_delete($file);
                return undef;
            }
            $app->log->info("--- The upload is done name=$name job_id=$job_id file=$file");
            unlink $file;
            $name;
        },
        sub {
            my ($sub, $err, @results) = @_;
        }
    );
    $self->render(json => { success => 1 });
}

sub db_restore {
    my $self = shift;

    my $store = $self->req->param('store');
    my $login = $self->req->param('login');
    my $password = $self->req->param('password');
    my $file = $self->req->param('file');
    my $new_name = $self->req->param('new_name');

    my $sub = Mojo::IOLoop::Subprocess->new;

    $sub->run(
        sub {
            my $sub = shift;
            my $app = $self->app;

            my $cb = $self->req->param('cb');
            my $job_id = $self->req->param('job_id');
            my $magic = $self->req->param('magic');

            return $self->render(json => { success => 0 }) unless $store;
            return $self->render(json => { success => 0 }) unless $login;
            return $self->render(json => { success => 0 }) unless $password;
            return $self->render(json => { success => 0 }) unless $file;
            return $self->render(json => { success => 0 }) unless $new_name;

            return $self->render(json => { success => 0 }) unless $cb;
            return $self->render(json => { success => 0 }) unless $job_id;
            return $self->render(json => { success => 0 }) unless $magic;

            $self->app->log->info("---The download begins file=$file job=$job_id");

            my $st = aStoreI->new($store, $login, $password);
            unless ($st->alive) {
                $self->app->log->info("---The download unsuccessful because store is dead store=$store job_id=$job_id");
                return undef;
            }

            my $res = $st->data_get($file, $app->config('datadir'));
            $app->log->info("---The download done store=$store job_id=$job_id file=$res");

            $app->log->info("---The restore begins job_id=$job_id new_name=$new_name file=$res");
            my $restore = $app->agent->db_restore($res, $new_name);
            $app->log->info("---The restore done job_id=$job_id new_name=$new_name file=$res");

        },
        sub {
            my ($sub, $err, @results) = @_;
        }
    );
    $self->render(json => { success => 1 });
}

1;

#-----------
#--- APP ---
#-----------

package DBagent;

use strict;
use warnings;
use Mojo::Base 'Mojolicious';

sub startup {
    my $self = shift;
}

1;

package main;

use POSIX qw(setuid setgid tzset tzname strftime);
use Mojo::Server::Prefork;
use Mojo::IOLoop::Subprocess;
use Mojo::Util qw(md5_sum b64_decode getopt dumper);
use Sys::Hostname qw(hostname);
use Digest::MD5 qw(md5_hex);
use File::Basename qw(basename dirname);
use Apache::Htpasswd;
use Cwd qw(getcwd abs_path);
use EV;

#------------
#--- MAIN ---
#------------

my $appname = 'dbagent';

#--------------
#--- GETOPT ---
#--------------

getopt
    'h|help' => \my $help,
    'r|request' => \my $request,
    'c|config=s' => \my $conffile,
    'f|nofork' => \my $nofork,
    'u|user=s' => \my $user,
    'g|group=s' => \my $group;

if ($help) {
    print qq(
Usage: app [OPTIONS]

Options
    -h | --help           This help
    -c | --config=path    Path to config file
    -u | --user=user      System owner of process
    -g | --group=group    System group 
    -f | --nofork         Dont fork process
    -r | --request        Generate key request

The options override options from configuration file
)."\n";
    exit 0;
}

if ($request) {
    my $salt = '425db905039f7a6559ce1115efa7d397';
    my $hash = 'da' . md5_hex(hostname . $salt);
    print "The copy key request: $hash\n";
    exit 0;
}

#------------------
#--- APP CONFIG ---
#------------------

my $server = Mojo::Server::Prefork->new;
my $app = $server->build_app('DBagent');
$app = $app->controller_class('DBagent::Controller');

$app->secrets(['6d578e43ba88260e0375a1a35fd7954b']);
$app->static->paths(['/usr/local/share/dbagent/public']);
$app->renderer->paths(['/usr/local/share/dbagent/templs']);

$app->config(conffile => $conffile || '/usr/local/etc/dbagent/dbagent.conf');
$app->config(pwdfile => '/usr/local/etc/dbagent/dbagent.pw');
$app->config(logfile => '/var/log/dbagent/dbagent.log');
$app->config(loglevel => 'debug');
$app->config(pidfile => '/var/run/dbagent/dbagent.pid');
$app->config(crtfile => '/usr/local/etc/dbagent/dbagent.crt');
$app->config(keyfile => '/usr/local/etc/dbagent/dbagent.key');

$app->config(user => $user || 'www');
$app->config(group => $group || 'www');

$app->config(listenaddr4 => '0.0.0.0');
#$app->config(listenaddr6 => '[::]');
$app->config(listenport => '8185');

$app->config(datadir => '/var/dbagent');
$app->config(timezone => 'Europe/Moscow');

$app->config(dbname => 'postgres');
$app->config(dbhost => '127.0.0.1');
$app->config(dblogin => 'postgres');
$app->config(dbpassword => 'password');


if (-r $app->config('conffile')) {
    $app->log->debug("Load configuration from ".$app->config('conffile'));
    my $c = aConfig->new($app->config('conffile'));
    my $hash = $c->read;

    foreach my $key (keys %$hash) {
        $app->config($key => $hash->{$key});
    }
}


#$ENV{MOJO_MAX_MESSAGE_SIZE} = 0; 
$ENV{MOJO_TMPDIR} = $app->config("datadir");
$app->max_request_size(10*1024*1024*1024);

#----------------
#--- TIMEZONE ---
#----------------
$ENV{TZ} = $app->config('timezone');
tzset;

#---------------
#--- HELPERS ---
#---------------

$app->helper('reply.exception' => sub { my $c = shift; $c->render(json => { message => 'exception', success => 0 }); });
$app->helper('reply.not_found' => sub { my $c = shift; $c->render(json => { message => 'not_found', success => 0 }); });

$app->helper(
    dbi => sub {
        my $engine;
        state $dbi = aDBI->new(
                database => $app->config('dbname'),
                host => $app->config('dbhost'),
                login => $app->config('dblogin'),
                password => $app->config('dbpassword'),
        );
});

$app->helper(
    agent => sub {
        state $user = aAgent->new($app->dbi); 
});

#--------------
#--- ROUTES ---
#--------------

my $r = $app->routes;

sub check_license {
    my $license = shift;
    return undef unless $license;

    my $hostname = hostname;
    my ($time, $hash) = split /:/, $license;

    return undef unless $time;
    return undef unless $license;

    eval { $time = $time + 0; };
    return undef if $@;
    return undef if time > $time;

    my $salt1 = '425db905039f7a6559ce1115efa7d397';
    my $salt2 = '5300a815b49146f52ffb49b4cac7e272';

    my $hash1 = 'da' . md5_hex($hostname . $salt1);
    my $hash2 = md5_hex($hash1 . $time . $salt2);

    if ($hash eq $hash2) {
        return 1;
    };
    return undef;
}

$r->add_condition(
    auth => sub {
        my ($route, $c) = @_;
        my $log = $c->app->log;
        my $authstr = $c->req->headers->authorization;
        my $pwdfile = $c->app->config('pwdfile');

        my $license = $c->app->config('key');
        unless (check_license($license)) {
            $log->info("Incorrect key");
            return undef;
        };
        my $a = aAuth->new($pwdfile);
        $log->info("Try auth user ". $a->username($authstr));
        $a->auth($authstr);

    }
);

$r->get('/hello')->over('auth')->to('controller#hello');

# --- DATABASE ---
$r->get('/db/list')->over('auth')->to('controller#db_list');
$r->get('/db/profile')->over('auth')->to('controller#db_profile');
$r->get('/db/create')->over('auth')->to('controller#db_create');
$r->get('/db/copy')->over('auth')->to('controller#db_copy');
$r->get('/db/drop')->over('auth')->to('controller#db_drop');

$r->get('/db/rename')->over('auth')->to('controller#db_rename');
$r->get('/db/owner')->over('auth')->to('controller#db_owner');

$r->get('/db/dump')->over('auth')->to('controller#db_dump');
$r->get('/db/restore')->over('auth')->to('controller#db_restore');

# --- USER ---

$r->get('/user/list')->over('auth')->to('controller#user_list');
$r->get('/user/profile')->over('auth')        ->to('controller#user_profile');
$r->get('/user/create')->over('auth')->to('controller#user_create');
$r->get('/user/drop')->over('auth')->to('controller#user_drop');

$r->get('/user/rename')->over('auth')->to('controller#user_rename');
$r->get('/user/password')->over('auth')->to('controller#user_password');

#----------------
#--- LISTENER ---
#----------------

my $tls = '?';
$tls .= 'cert='.$app->config('crtfile');
$tls .= '&key='.$app->config('keyfile');

my $listen4;
if ($app->config('listenaddr4')) {
    $listen4 = "https://";
    $listen4 .= $app->config('listenaddr4').':'.$app->config('listenport');
    $listen4 .= $tls;
}

my $listen6;
if ($app->config('listenaddr6')) {
    $listen6 = "https://";
    $listen6 .= $app->config('listenaddr6').':'.$app->config('listenport');
    $listen6 .= $tls;
}

my @listen;
push @listen, $listen4 if $listen4;
push @listen, $listen6 if $listen6;

$server->listen(\@listen);
$server->heartbeat_interval(3);
$server->heartbeat_timeout(60);
#$server->spare(2);
#$server->workers(2);

#--------------
#--- DAEMON ---
#--------------

unless ($nofork) {
    my $user = $app->config('user');
    my $group = $app->config('group');
    my $d = aDaemon->new($user, $group);

    $d->fork;

    $app->log(Mojo::Log->new( 
                path => $app->config('logfile'),
                level => $app->config('loglevel')
    ));
}

$server->pid_file($app->config('pidfile'));

#---------------
#--- WEB LOG ---
#---------------

$app->hook(before_dispatch => sub {
        my $c = shift;

        my $remote_address = $c->tx->remote_address;
        my $method = $c->req->method;

        my $base = $c->req->url->base->to_string;
        my $path = $c->req->url->path->to_string;
        my $loglevel = $c->app->log->level;
        my $url = $c->req->url->to_abs->to_string;

        unless ($loglevel eq 'debug') {
            #$c->app->log->info("$remote_address $method $base$path");
            $c->app->log->info("$remote_address $method $url");
        }
        if ($loglevel eq 'debug') {
            $c->app->log->debug("$remote_address $method $url");
        }
});

#----------------------
#--- SIGNAL HANDLER ---
#----------------------

local $SIG{HUP} = sub {
    $app->log->info('Catch HUP signal'); 
    $app->log(Mojo::Log->new(
                    path => $app->config('logfile'),
                    level => $app->config('loglevel')
    ));
};

$server->run;
#EOF
