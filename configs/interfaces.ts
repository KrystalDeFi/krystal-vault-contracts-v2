export interface IConfig {
  autoVerifyContract?: boolean;
  sleepTime?: number;
  vault: {
    enabled?: boolean;
    autoVerifyContract?: boolean;
  };
  vaultAutomator: {
    enabled?: boolean;
    autoVerifyContract?: boolean;
  };
  vaultFactory: {
    enabled?: boolean;
    autoVerifyContract?: boolean;
  };
  configManager?: {
    enabled?: boolean;
    autoVerifyContract?: boolean;
  };
  poolOptimalSwapper?: {
    enabled?: boolean;
    autoVerifyContract?: boolean;
  };
  lpStrategy?: {
    enabled?: boolean;
    autoVerifyContract?: boolean;
  };
  wrapToken?: string;
  stableTokens?: string[];
  peggedTokens?: string[];
  automatorAddress?: string;
  // For platform fee recipient
  platformFeeRecipient?: string;
  // For platform fee in basis point
  platformFeeBasisPoint?: number;
}
