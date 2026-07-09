import { createApp } from '@backstage/frontend-defaults';
import catalogImportPlugin from '@backstage/plugin-catalog-import/alpha';
import catalogPlugin from '@backstage/plugin-catalog/alpha';
import kubernetesPlugin from '@backstage/plugin-kubernetes/alpha';
import notificationsPlugin from '@backstage/plugin-notifications/alpha';
import scaffolderPlugin from '@backstage/plugin-scaffolder/alpha';
import { navModule } from './modules/nav';

export default createApp({
  features: [
    catalogPlugin,
    catalogImportPlugin,
    kubernetesPlugin,
    notificationsPlugin,
    scaffolderPlugin,
    navModule,
  ],
});
