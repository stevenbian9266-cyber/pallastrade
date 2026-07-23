# see: https://docs.adyen.com/partners/application-information/?tab=partner-built_0_1#application-information-fields
# some endpoints used in PallasTradeAdyen does not support applicationInfo (e.g. creating webhook)
module PallasTradeAdyen
  class ApplicationInfoPresenter
    def to_h
      {
        applicationInfo: {
          externalPlatform: {
            name: 'PallasTrade Commerce',
            version: PallasTrade.version,
            integrator: 'Steven Bian'
          },
          merchantApplication: {
            name: defined?(PallasTradeEnterprise) ? 'Enterprise Edition' : 'Community Edition',
            version: PallasTradeAdyen.version
          }
        }
      }
    end
  end
end
