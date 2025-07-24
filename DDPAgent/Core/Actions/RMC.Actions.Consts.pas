unit RMC.Actions.Consts;

interface

const

  // Agent specific actions
  ACTION_AGENT_SUBSCRIBING = 'ACTION_AGENT_SUBSCRIBING';
  ACTION_AGENT_SUBSCRIBED = 'ACTION_AGENT_SUBSCRIBED';
  ACTION_AGENT_SUBSCRIBE_ERROR = 'ACTION_AGENT_SUBSCRIBE_ERROR';

  // Session management actions
  ACTION_SESSION_OPENING = 'ACTION_SESSION_OPENING';
  ACTION_SESSION_OPENED = 'ACTION_SESSION_OPENED';
  ACTION_SESSION_CLOSED = 'ACTION_SESSION_CLOSED';
  ACTION_SESSION_ERROR = 'ACTION_SESSION_ERROR';
  ACTION_SESSION_LIMIT_REACHED = 'ACTION_SESSION_LIMIT_REACHED';

  // Command execution actions
  ACTION_COMMAND_EXECUTING = 'ACTION_COMMAND_EXECUTING';
  ACTION_COMMAND_OUTPUT = 'ACTION_COMMAND_OUTPUT';
  ACTION_COMMAND_COMPLETED = 'ACTION_COMMAND_COMPLETED';
  ACTION_COMMAND_ERROR = 'ACTION_COMMAND_ERROR';

  //Subscription
  SESSIONS_SUBSCRIPTION = 'agent.sessions';
  COMMANDS_SUBSCRIPTION = 'agent.commands';
  // Agent actions
  TEST_PING = 'test.ping';
  // Agent methods
  AGENT_REGISTER = 'agent.register';

  SESSION_CLOSE = 'sessions.close';
  SESSION_CLOSE_ALL = 'sessions.closeAll';
  SESSION_HEARTBEAT = 'sessions.heartbeat';
  SESSION_STATUS = 'session.sessionStatus';

  // Command methods
  COMMAND_EXECUTION = 'commands.execution';
  COMMAND_OUTPUT = 'commands.sendOutput';
  COMMAND_COMPLETED = 'commands.commandComplete';
  COMMAND_SEND_ERROR = 'commands.sendError';

implementation

end.
