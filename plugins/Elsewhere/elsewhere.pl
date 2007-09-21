# $Id$

package MT::Plugin::Elsewhere;
use strict;
use warnings;
use base qw( MT::Plugin );

use Carp qw( croak );
use WWW::SocialNetworks;

our $VERSION = '1.0';

my $plugin = __PACKAGE__->new({
    id          => 'elsewhere',
    name        => 'Elsewhere',
    version     => $VERSION,
    author_name => 'Benjamin Trott',
    author_link => 'http://www.sixapart.com/',
    description => 'Elsewhere allows you to link to your other profiles/websites online. You can add other websites in your Edit Profile screen.',
});
MT->add_plugin( $plugin );

sub init_registry {
    my $plugin = shift;
    $plugin->registry( {
        applications => {
            cms => {
                methods => {
                    other_profiles => sub {
                        $plugin->other_profiles( @_ ),
                    },
                    add_other_profile => sub {
                        $plugin->add_other_profile( @_ ),
                    },
                    remove_other_profile => sub {
                        $plugin->remove_other_profile( @_ ),
                    },
                    embed_profiles => sub {
                        $plugin->embed_profiles( @_ ),
                    }
                },
            },
        },
        callbacks => {
            'MT::App::CMS::template_source.users_content_nav' => sub {
                $plugin->insert_profile_link( @_ );
            },
        },
        tags => {
            function => {
                OtherProfileVar => \&tag_OtherProfileVar,
            },
            block => {
                OtherProfiles => \&tag_OtherProfiles,
            },
        },
    } );
}

sub tag_OtherProfiles {
    my( $ctx, $args, $cond ) = @_;
    my $author = $args->{author}
        or return $ctx->error( 'author argument is required' );
    my( $user ) = MT::Author->search({ name => $author })
        or return $ctx->error( 'no such user ' . $author );
    my $out = "";
    my $builder = $ctx->stash( 'builder' );
    my $tokens = $ctx->stash( 'tokens' );
    for my $profile ( @{ $user->other_profiles } ) {
        $ctx->stash( other_profile => $profile );
        $out .= $builder->build( $ctx, $tokens, $cond );
    }
    return $out;
}

sub tag_OtherProfileVar {
    my( $ctx, $args ) = @_;
    my $profile = $ctx->stash( 'other_profile' )
        or return $ctx->error( 'No profile defined in ProfileVar' );
    my $var = $args->{name} || 'uri';
    return defined $profile->{ $var } ? $profile->{ $var } : '';
}

sub insert_profile_link {
    my $plugin = shift;
    my( $cb, $app, $html_ref ) = @_;
    my $base_uri = $app->uri;
    my $mode = $app->mode;
    my $active = $mode eq 'other_profiles' ? ' class="active"' : '';
    if ( $active ) {
        $$html_ref =~ s/<li class="active">/<li>/g;
    }
    ## Somewhat nasty: we need to match in users_content_nav.tmpl under
    ## only certain scenarios, i.e. in the Author Profile cases of that
    ## template. Yuck.
    $$html_ref =~ s/(<li[^>]*>.*?author_id=.*?<__trans phrase="Permissions"><\/a><\/li>)/$1\n<li$active><a href="$base_uri?__mode=other_profiles">Other Profiles<\/a><\/li>/g;
}

sub other_profiles {
    my $plugin = shift;
    my( $app ) = @_;
    my $tmpl = $plugin->load_tmpl( 'other_profiles.tmpl' );
    my $networks = WWW::SocialNetworks->all;
    return $app->build_page( $tmpl, {
        id          => $app->user->id,
        profiles    => $app->user->other_profiles,
        networks    => [
            map { +{
                type    => $_,
                label   => $networks->{ $_ }[ 0 ],
            } } sort keys %$networks,
        ],
    } );
}

sub add_other_profile {
    my $plugin = shift;
    my( $app ) = @_;
    $app->validate_magic or return;

    my( $ident, $uri, $label, $type );
    if ( $type = $app->param( 'profile_type' ) ) {
        my $network = WWW::SocialNetworks->get( $type )
            or croak "Unknown network $type";
        $label = $network->name . ' Profile';
        $ident = $app->param( 'profile_id' );
        $uri = $network->uri_for( $ident );
    } else {
        $ident = $uri = $app->param( 'profile_uri' );
        $label = $app->param( 'profile_label' );
        $type = 'website';
    }

    $app->user->add_profile({
        type    => $type,
        ident   => $ident,
        label   => $label,
        uri     => $uri,
    });

    return $app->redirect( $app->uri( mode => 'other_profiles' ) );
}

sub remove_other_profile {
    my $plugin = shift;
    my( $app ) = @_;
    $app->validate_magic or return;

    if ( my $ident = $app->param('ident') ) {
        ( my( $type ), $ident ) = split /:/, $ident;
        $app->user->remove_profile( $type, $ident );
    }
    
    return $app->redirect( $app->uri( mode => 'other_profiles' ) );
}

sub embed_profiles {
    my $plugin = shift;
    my( $app ) = @_;
    my $name = $app->user->name;
    my $html = <<HTML;
<div class="widget-elsewhere widget">
    <h3 class="widget-header">Elsewhere</h3>
    <link rel="stylesheet" type="text/css" href="<mt:staticwebpath>plugins/Elsewhere/css/networks.css" />
    <ul id="elsewhere-profiles" class="network">
    <mt:otherprofiles author="$name">
        <li>
            <a href="<mt:otherprofilevar name="uri" escape="html">" rel="me" class="<mt:otherprofilevar name="type">"><mt:otherprofilevar name="label" escape="html"></a>
        </li>
    </mt:otherprofiles>
    </ul>
</div>
HTML
    my $tmpl = $plugin->load_tmpl( 'embed.tmpl' );
    return $app->build_page( $tmpl, { embed => $html } );
}

MT::Author->install_meta({
    columns => [
        'other_profiles',
    ],
});

sub MT::Author::other_profiles {
    my $user = shift;
    my( $type ) = @_;
    require Storable;
    my $profiles = Storable::thaw( $user->meta( 'other_profiles' ) ) || [];
    return $type ?
        [ grep { $_->{type} eq $type } @$profiles ] :
        $profiles;
}

sub MT::Author::add_profile {
    my $user = shift;
    my( $profile ) = @_;
    my $profiles = $user->other_profiles;
    push @$profiles, $profile;
    require Storable;
    $user->meta( other_profiles => Storable::nfreeze( $profiles ) );
    $user->save;
}

sub MT::Author::remove_profile {
    my $user = shift;
    my( $type, $ident ) = @_;
    my $profiles = [ grep {
        $_->{type} ne $type || $_->{ident} ne $ident
    } @{ $user->other_profiles } ];
    require Storable;
    $user->meta( other_profiles => Storable::nfreeze( $profiles ) );
    $user->save;
}

1;