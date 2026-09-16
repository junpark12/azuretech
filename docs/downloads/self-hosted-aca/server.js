const express = require('express');
const app = express();

// App Service supplies PORT; local development defaults to 8080.
const port = process.env.PORT || 8080;

app.get('/', (req, res) => {
  res.status(200).json({
    message: 'Hello from Azure App Service!',
    deployedVia: 'GitHub Actions self-hosted runner (Azure Container Apps + KEDA)',
    timestamp: new Date().toISOString(),
  });
});

app.get('/health', (req, res) => {
  res.status(200).send('OK');
});

app.listen(port, () => {
  console.log(`Server listening on port ${port}`);
});
