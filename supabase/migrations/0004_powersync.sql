-- Coach — publication de réplication pour PowerSync.
-- PowerSync lit les changements via cette publication (elle doit s'appeler `powersync`).
-- Le rôle de réplication et son mot de passe se créent à la main : voir le README.

create publication powersync for table
  public.clubs,
  public.memberships,
  public.training_groups,
  public.athletes,
  public.group_athletes,
  public.invitations,
  public.session_types,
  public.sessions,
  public.session_blocks,
  public.events,
  public.event_groups;
